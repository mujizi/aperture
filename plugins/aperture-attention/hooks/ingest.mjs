#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdir, readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const baseUrl = `http://127.0.0.1:${process.env.APERTURE_PORT || "4317"}`;

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const text = Buffer.concat(chunks).toString("utf8").trim();
  return text ? JSON.parse(text) : {};
}

async function healthy() {
  try {
    const response = await fetch(`${baseUrl}/api/health`, {
      signal: AbortSignal.timeout(900)
    });
    return response.ok;
  } catch {
    return false;
  }
}

async function ensureServer() {
  if (await healthy()) return;
  const pluginRoot = process.env.PLUGIN_ROOT || path.resolve(import.meta.dirname, "..");
  const pluginData = process.env.PLUGIN_DATA || path.join(os.homedir(), ".aperture");
  const runtime = path.join(pluginRoot, "runtime", "server.mjs");
  const configDir = path.join(os.homedir(), ".aperture");
  await mkdir(configDir, { recursive: true });
  await mkdir(pluginData, { recursive: true });

  const child = spawn(process.execPath, [runtime], {
    cwd: configDir,
    detached: true,
    stdio: "ignore",
    env: {
      ...process.env,
      APERTURE_DATA_DIR: pluginData,
      APERTURE_WEB_DIR: path.join(pluginRoot, "runtime", "web")
    }
  });
  child.unref();

  for (let attempt = 0; attempt < 16; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    if (await healthy()) return;
  }
  throw new Error(`Aperture daemon did not start from ${runtime}`);
}

async function post(route, body, timeout = 7000) {
  const response = await fetch(`${baseUrl}${route}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeout)
  });
  if (!response.ok) throw new Error(`Aperture ${route} failed (${response.status})`);
  return response.json();
}

async function maybeOpenSidecar() {
  if (process.env.APERTURE_OPEN_ON_SESSION === "false") return;
  const pluginRoot = process.env.PLUGIN_ROOT || path.resolve(import.meta.dirname, "..");
  const script = path.join(pluginRoot, "scripts", "open-sidecar.mjs");
  const child = spawn(process.execPath, [script], {
    detached: true,
    stdio: "ignore",
    env: process.env
  });
  child.unref();
}

async function main() {
  const input = await readStdin();
  await ensureServer();
  await post("/api/events", input);

  if (input.hook_event_name === "SessionStart") {
    await maybeOpenSidecar();
  }

  if (input.hook_event_name === "Stop") {
    await post(
      "/api/analyze",
      { runId: input.session_id, turnId: input.turn_id },
      65000
    );
  }

  process.stdout.write("{}");
}

main().catch((error) => {
  process.stderr.write(`Aperture hook: ${error instanceof Error ? error.message : String(error)}\n`);
  process.stdout.write("{}");
});
