#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_source="$project_dir/.build/macos/Aperture.app"
app_target="/Applications/Aperture.app"
agent_source="$project_dir/native/ApertureCompanion/com.aperture.attention.plist"
agent_dir="$HOME/Library/LaunchAgents"
agent_target="$agent_dir/com.aperture.attention.plist"
launch_domain="gui/$(id -u)"
launch_label="com.aperture.attention"
health_url="http://127.0.0.1:4317/api/health"
models_url="http://127.0.0.1:4317/api/models"
catalog_file=$(mktemp "${TMPDIR:-/tmp}/aperture-models.XXXXXX")
trap 'rm -f "$catalog_file"' EXIT

aperture_app_pids() {
    pgrep -f '/Aperture\.app/Contents/MacOS/Aperture$' 2>/dev/null || true
}

aperture_daemon_pids() {
    for listener_pid in $(lsof -tiTCP:4317 -sTCP:LISTEN 2>/dev/null || true); do
        listener_command=$(ps -p "$listener_pid" -o command= 2>/dev/null || true)
        if [[ "$listener_command" == *"Aperture.app/Contents/Resources/runtime/server.mjs"* ]] \
            || [[ "$listener_command" == *"aperture-attention/runtime/server.mjs"* ]]; then
            echo "$listener_pid"
        else
            echo "Port 4317 is occupied by an unrelated process: $listener_command" >&2
            return 1
        fi
    done
}

wait_until_stopped() {
    local running_apps running_daemons
    for _attempt in {1..30}; do
        running_apps=$(aperture_app_pids)
        running_daemons=$(aperture_daemon_pids) || return 1
        if [[ -z "$running_apps" && -z "$running_daemons" ]]; then
            return 0
        fi
        /bin/sleep 0.1
    done

    # Both targets have been resolved to Aperture-owned processes above. Force
    # only those exact leftovers after the graceful shutdown window expires.
    for stale_pid in $running_apps $running_daemons; do
        kill -KILL "$stale_pid" >/dev/null 2>&1 || true
    done
    for _attempt in {1..20}; do
        running_apps=$(aperture_app_pids)
        running_daemons=$(aperture_daemon_pids) || return 1
        if [[ -z "$running_apps" && -z "$running_daemons" ]]; then
            return 0
        fi
        /bin/sleep 0.1
    done
    echo "Aperture did not stop completely" >&2
    return 1
}

cd "$project_dir"
npm run build:mac

# Disable the login agent first so it cannot relaunch the installed copy while
# the development build and its daemon are being replaced.
launchctl bootout "$launch_domain/$launch_label" >/dev/null 2>&1 || true
/usr/bin/osascript -e 'tell application "Aperture" to quit' >/dev/null 2>&1 || true
current_daemon_pids=$(aperture_daemon_pids)
for aperture_pid in $(aperture_app_pids) $current_daemon_pids; do
    kill "$aperture_pid" >/dev/null 2>&1 || true
done
wait_until_stopped

if [[ -d "$app_target" ]]; then
    installed_bundle_id=$(
        plutil -extract CFBundleIdentifier raw \
            "$app_target/Contents/Info.plist" 2>/dev/null || true
    )
    if [[ "$installed_bundle_id" != "com.aperture.attention" ]]; then
        echo "Refusing to replace unexpected app at $app_target" >&2
        exit 1
    fi
    rm -rf "$app_target"
fi
ditto "$app_source" "$app_target"

mkdir -p "$agent_dir"
cp "$agent_source" "$agent_target"
plutil -lint "$agent_target" >/dev/null

launchctl bootstrap "$launch_domain" "$agent_target"
launchctl enable "$launch_domain/$launch_label"
launchctl kickstart -k "$launch_domain/$launch_label"

health_payload=""
for _attempt in {1..60}; do
    health_payload=$(curl -fsS --max-time 1 "$health_url" 2>/dev/null || true)
    if [[ "$health_payload" == *'"service":"aperture-attention"'* ]] \
        && [[ "$health_payload" == *'"public-model-catalog-v1"'* ]]; then
        break
    fi
    /bin/sleep 0.2
done
if [[ "$health_payload" != *'"public-model-catalog-v1"'* ]]; then
    echo "Aperture restarted, but the current daemon did not pass its health check" >&2
    exit 1
fi

curl -fsS --max-time 25 "$models_url" -o "$catalog_file"
catalog_summary=$(node -e '
const { readFileSync } = require("node:fs");
const payload = JSON.parse(readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(payload.models) || payload.models.length === 0) process.exit(1);
const free = payload.models.filter((model) => model.isFree).length;
process.stdout.write(`${payload.models.length} models (${free} free)`);
' "$catalog_file")

echo "$app_target"
echo "$agent_target"
echo "Aperture fully restarted: $catalog_summary"
