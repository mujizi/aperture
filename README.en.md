# Aperture

> Make model output fit human attention bandwidth.

English · [简体中文](README.md)

Aperture is a macOS attention companion for Codex. After each completed turn, it reads the question and final answer, then uses OpenRouter to produce a glanceable attention brief: the most important result, genuine decisions, real blockers, and the most useful flow, comparison, or metrics.

It does not run tasks for you, and it is not a second chat window. It appears after Codex finishes so you can quickly answer: **What happened? Do I need to step in? What comes next?**

## Quick start

### 1. Check the requirements

The current `v0.2.0` preview requires:

- An Apple Silicon Mac (M1/M2/M3/M4 and later; Intel Macs are not supported yet)
- macOS 13 Ventura or later
- [Codex](https://openai.com/codex/); Aperture watches local tasks in `~/.codex/sessions`
- Node.js 22 or later (the current LTS is recommended)
- An OpenRouter API key and a model that supports structured output
- Network access to the OpenRouter API

> A model configured in Codex is not automatically available to Aperture. Aperture currently calls OpenRouter independently, so its key and model must be configured inside the app.

Check Node.js:

```bash
node --version
```

If it is not installed, use the [official Node.js installer](https://nodejs.org/en/download) or Homebrew:

```bash
brew install node
```

### 2. Install Aperture

1. Download `Aperture-v0.2.0-macos-arm64.dmg` or `.zip` from [Releases](https://github.com/mujizi/aperture/releases/latest).
2. Move `Aperture.app` to `/Applications`.
3. On first launch, Control-click or right-click Aperture and choose **Open**.
4. If macOS still blocks it, approve the app in **System Settings → Privacy & Security**.

This preview is not notarized with an Apple Developer ID, so macOS requires an explicit first-launch confirmation. Do not use repackaged builds from outside this repository.

### 3. Configure the model

1. Launch Aperture:

   ```bash
   open -a Aperture
   ```

2. Open settings from the Aperture menu bar item.
3. Choose an OpenRouter model and enter your API key.
4. Run the connection test, then enable monitoring.

The key is used only for OpenRouter requests and stored in `~/.aperture/.env` with `0600` permissions. The local service listens only on `127.0.0.1:4317`.

### 4. Use Codex normally

Continue working in Codex as usual. After each completed turn:

- Aperture enters its processing state and presents the new brief;
- use the left and right arrow keys to move through older or newer results;
- adjust focus to change the visual weight of the result, supporting details, and context;
- collapse the panel into a draggable bubble and click it to expand again;
- copy selected text or the full derived Markdown brief.

To start Aperture automatically after a restart, add it in **System Settings → General → Login Items**.

## What Aperture helps you do

### Turn long answers into glanceable outcomes

Aperture selects one primary result from the complete final answer, then retains only evidence, risks, and actions that affect judgment. It does not mechanically shorten and preserve every section of the original response.

### Make decisions and blockers visible

A `decision` appears only when a real choice changes what can happen next. A `blocker` appears only when the result is unusable or progress cannot continue. Ordinary suggestions are not promoted into false urgency.

### Match the view to the relationship

Aperture chooses a representation that fits the content:

- `statement` for a standalone conclusion, risk, reason, or action;
- `flow` for a real sequence, causal chain, or process;
- `comparison` for options or before-and-after states with shared dimensions;
- `metrics` when numbers directly explain the result.

### Keep completion history across tasks

Briefs are stored locally in actual completion order. Use the arrow keys to review sequential or concurrent tasks without reopening every original conversation.

## How it works

```text
Codex session JSONL (local)
          │
          ▼
Session Watcher
          │
          ├── cleaned question
          └── complete final answer
                    │
                    ▼
              OpenRouter model
                    │
                    ▼
          AttentionScene v2
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
 macOS floating companion  Markdown / MCP
```

The attention model receives only the cleaned question, the complete final answer, and the focus level. Tool calls, tool output, and Aperture's internal events are not sent to the model. Events, settings, and history are stored under `~/.aperture`.

See [Architecture](docs/ARCHITECTURE.md) for the protocol and local API.

## Privacy and security

- The service binds only to the local loopback interface and is not exposed to the LAN.
- The OpenRouter key is never returned through read APIs, results, or MCP.
- The key is stored in `~/.aperture/.env` with `0600` permissions.
- Raw Codex sessions and Aperture history remain local.
- Requests to OpenRouter can contain your current question and the Codex final answer. Do not enable monitoring for projects where third-party model processing is not allowed.
- Tool logs are not sent to the model. This reduces noise and exposure, but Aperture cannot discover an important failure that exists only in tool output and was omitted from the final answer.

## Current limitations

- OpenRouter is the only supported provider; Codex model credentials are not reused.
- The current release supports Apple Silicon only.
- Node.js 22+ must be available on the system; it is not bundled in the app yet.
- The preview uses an ad-hoc signature and is not Apple-notarized.
- Quality, latency, and regional availability depend on the selected OpenRouter model.
- The model can occasionally mistake parallel changes for a flow or produce an unnecessary comparison.
- Turns completed while monitoring is disabled are not backfilled automatically.

## Optional Codex plugin

The macOS companion works without the plugin because the Session Watcher is the primary capture path. `plugins/aperture-attention` additionally provides:

- optional Codex lifecycle hooks;
- a skill for reading the latest Aperture result;
- local MCP configuration.

The plugin is an advanced integration and is not required for the quick start.

## Build from source

Development requires Node.js 22+, npm, Python 3, and Xcode Command Line Tools with `swiftc`.

```bash
git clone https://github.com/mujizi/aperture.git
cd aperture
npm install
npm run setup:validator
npm run typecheck
npm test
npm run build
```

Build and install locally:

```bash
npm run install:mac
```

Create the `.dmg`, `.zip`, and SHA-256 files used by GitHub Releases:

```bash
npm run package:mac
```

Artifacts are written to `.build/release/`.

## Design philosophy

### 1. Human attention is the final bandwidth

Models can generate increasingly long answers, but people should not have to parse every full response after every turn. Aperture exists to decide what deserves attention now, not to generate more content.

### 2. A peripheral companion, not a second workspace

Aperture appears automatically, is readable without navigation, scrolls naturally, and collapses into a bubble. It does not ask users to learn a new workspace or attempt to replace Codex.

### 3. Preserve semantics before choosing a visual form

Flows are used only for real flows, comparisons only for shared dimensions, and metrics only when numbers explain the outcome. Open-ended agent output remains text-first; visuals reveal relationships rather than decorate them.

### 4. Failure must remain visible

If the model is missing, times out, fails, or returns invalid content, Aperture shows an explicit error. It does not disguise failure with a rule-based summary or the untouched original answer.

### 5. Focus does not delete facts

Focus changes visual weight without calling the model again or hiding genuine decisions and blockers. Users can lower background noise while retaining the information already selected.

### 6. Local-first without pretending to be fully offline

Capture, storage, history, and rendering are local. Semantic compression explicitly depends on OpenRouter today. The product should keep this boundary visible so users know which data leaves the machine.

## Repository layout

```text
src/core/                         Event and AttentionScene protocols
src/server/                       Session watcher, storage, model, MCP, and HTTP API
src/web/                          Continuous brief, relationship views, and history
native/ApertureCompanion/         macOS panel, bubble, and menu bar app
plugins/aperture-attention/       Optional hooks, skill, MCP, and runtime
scripts/                          Build, install, and release packaging
```

See [CURRENT_STATE.md](docs/CURRENT_STATE.md) for the current implementation state and known design issues.
