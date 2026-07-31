import { cp, mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { build } from "esbuild";

const root = process.cwd();
const pluginRuntime = path.join(root, "plugins", "aperture-attention", "runtime");
const serverOut = path.join(pluginRuntime, "server.mjs");
const webOut = path.join(pluginRuntime, "web");

await rm(pluginRuntime, { recursive: true, force: true });
await mkdir(pluginRuntime, { recursive: true });

await build({
  entryPoints: [path.join(root, "src", "server", "index.ts")],
  outfile: serverOut,
  bundle: true,
  platform: "node",
  target: "node22",
  format: "esm",
  sourcemap: false,
  minify: false,
  banner: {
    js: 'import { createRequire as __apertureCreateRequire } from "node:module"; const require = __apertureCreateRequire(import.meta.url);'
  }
});

await cp(path.join(root, "dist", "web"), webOut, { recursive: true });
console.log(`Bundled Aperture runtime at ${pluginRuntime}`);
