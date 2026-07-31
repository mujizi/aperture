import { cp, mkdir } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const root = process.cwd();
const source = path.join(root, "plugins", "aperture-attention");
const targetParent = path.join(os.homedir(), "plugins");
const target = path.join(targetParent, "aperture-attention");
const skillRoot = path.join(
  os.homedir(),
  ".codex",
  "skills",
  ".system",
  "plugin-creator"
);
const creator = path.join(skillRoot, "scripts", "create_basic_plugin.py");
const cachebuster = path.join(skillRoot, "scripts", "update_plugin_cachebuster.py");
const validator = path.join(skillRoot, "scripts", "validate_plugin.py");
const marketplace = path.join(os.homedir(), ".agents", "plugins", "marketplace.json");
const python = path.join(root, ".venv", "bin", "python");

function run(command, args) {
  const result = spawnSync(command, args, { stdio: "inherit" });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed with exit ${result.status}`);
  }
}

await mkdir(targetParent, { recursive: true });
run(python, [
  creator,
  "aperture-attention",
  "--with-skills",
  "--with-hooks",
  "--with-scripts",
  "--with-assets",
  "--with-mcp",
  "--with-marketplace",
  "--force"
]);
await cp(source, target, { recursive: true, force: true });
run(python, [cachebuster, target]);
run(python, [validator, target]);

let marketplaceName = "personal";
try {
  const result = spawnSync(
    python,
    [
      path.join(skillRoot, "scripts", "read_marketplace_name.py"),
      "--marketplace-path",
      marketplace
    ],
    { encoding: "utf8" }
  );
  if (result.status === 0 && result.stdout.trim()) marketplaceName = result.stdout.trim();
} catch {
  // The default personal marketplace name is a safe fallback.
}

run("codex", ["plugin", "add", `aperture-attention@${marketplaceName}`]);
console.log(`Installed Aperture Attention from ${target}`);
