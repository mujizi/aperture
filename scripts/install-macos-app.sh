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

cd "$project_dir"
npm run build:mac

/usr/bin/osascript -e 'tell application "Aperture" to quit' >/dev/null 2>&1 || true
for listener_pid in $(lsof -tiTCP:4317 -sTCP:LISTEN 2>/dev/null || true); do
    listener_command=$(ps -p "$listener_pid" -o command= 2>/dev/null || true)
    if [[ "$listener_command" == *"Aperture.app/Contents/Resources/runtime/server.mjs"* ]] \
        || [[ "$listener_command" == *"aperture-attention/runtime/server.mjs"* ]]; then
        kill "$listener_pid" >/dev/null 2>&1 || true
    fi
done
/bin/sleep 0.2

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

launchctl bootout "$launch_domain/com.aperture.attention" >/dev/null 2>&1 || true
launchctl bootstrap "$launch_domain" "$agent_target"
launchctl enable "$launch_domain/com.aperture.attention"
launchctl kickstart -k "$launch_domain/com.aperture.attention"

echo "$app_target"
echo "$agent_target"
