#!/usr/bin/env node
import { spawn } from "node:child_process";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const url = `http://127.0.0.1:${process.env.APERTURE_PORT || "4317"}/?surface=companion`;
const stateDir = process.env.PLUGIN_DATA || path.join(os.homedir(), ".aperture");
const markerPath = path.join(stateDir, "sidecar-opened-at");

async function recentlyOpened() {
  try {
    const timestamp = Number(await readFile(markerPath, "utf8"));
    return Date.now() - timestamp < 60_000;
  } catch {
    return false;
  }
}

async function main() {
  await mkdir(stateDir, { recursive: true });
  if (await recentlyOpened()) return;

  const applications = [
    "/Applications/Aperture.app",
    path.join(os.homedir(), "Applications", "Aperture.app")
  ];
  const companion = await Promise.all(
    applications.map(async (candidate) => {
      try {
        await access(candidate);
        return candidate;
      } catch {
        return null;
      }
    })
  ).then((candidates) => candidates.find(Boolean));

  if (companion) {
    const child = spawn("open", [companion], {
      detached: true,
      stdio: "ignore"
    });
    child.unref();
    await writeFile(markerPath, String(Date.now()), "utf8");
    return;
  }

  const chrome = "/Applications/Google Chrome.app";
  try {
    await access(chrome);
    const child = spawn(
      "open",
      [
        "-na",
        "Google Chrome",
        "--args",
        `--app=${url}`,
        "--window-size=430,900",
        "--window-position=980,80"
      ],
      { detached: true, stdio: "ignore" }
    );
    child.unref();
  } catch {
    const child = spawn("open", [url], { detached: true, stdio: "ignore" });
    child.unref();
  }
  await writeFile(markerPath, String(Date.now()), "utf8");
}

void main();
