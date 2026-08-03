<p align="center">
  <img src="native/ApertureCompanion/AppIcon.svg" width="112" alt="Aperture app icon">
</p>

<h1 align="center">Aperture</h1>

<p align="center">The attention layer between human input bandwidth and model output bandwidth.</p>

<p align="center"><a href="README.md">CN</a> · <strong>EN</strong></p>

Aperture is a macOS attention layer between human input bandwidth and model output bandwidth. After Codex completes a turn, it remaps the complete final answer into an `AttentionScene` that a person can absorb quickly: the primary outcome, genuine decisions, blockers, and the relationships and context that still matter.

**It is not a summarizer.** Summarization tries to shorten source text; Aperture decides what should be seen first, what must remain visible, and what can recede into context at the person's current bandwidth.

The attention pass is independent from the model used by Codex. Through OpenRouter, you can choose models from different upstream providers—including inexpensive, fast models—and turn monitoring on or off at any time.

## Product tour

<p align="center">
  <img src="docs/images/aperture-workflow.svg" width="100%" alt="Aperture workflow from a completed Codex turn to an automatically generated attention scene">
</p>

Aperture watches local Codex tasks in the background. When a turn completes, it automatically takes the current question and complete final answer, uses an independent attention model to create a structured `AttentionScene`, and presents what deserves attention first in the floating companion. There is nothing to copy, paste, or trigger manually.

### Collapse and expand: present when needed, peripheral when not

<table>
  <tr>
    <td width="50%" align="center"><strong>Collapsed</strong></td>
    <td width="50%" align="center"><strong>Expanded</strong></td>
  </tr>
  <tr>
    <td><img src="docs/images/aperture-collapsed.png" width="100%" alt="Aperture collapsed into a transparent golden pixel-cat icon at the edge of the desktop"></td>
    <td><img src="docs/images/aperture-expanded.jpg" width="100%" alt="Aperture expanded into a floating reading panel with the cat thumbnail in its header"></td>
  </tr>
  <tr>
    <td valign="top">Collapse the companion into a frameless transparent golden pixel-cat icon. When a new result arrives, the cat briefly focuses its aperture lens and blinks once.</td>
    <td valign="top">Click the bubble to restore the floating window and read beside the current task without switching to a second workspace.</td>
  </tr>
</table>

### Automatic attention pass: reorder reading priority instead of truncating text

<p align="center">
  <img src="docs/images/aperture-attention-ui.png" width="420" alt="Aperture attention scene with the cat thumbnail in its header, showing a primary result, relationships, steps, and verification evidence">
</p>

The interface follows human reading priority from top to bottom:

| UI component | The question it answers |
| --- | --- |
| **Primary result** | What did this turn actually accomplish? The largest type and whitespace put the conclusion first. |
| **Decision / blocker** | Is there a real choice that needs the user, or a problem that makes the result unusable? These stay pinned only when they genuinely exist. |
| **Relationship view** | Are the facts connected as steps, causes, comparisons, or metrics? Aperture chooses the matching `flow`, `comparison`, or `metrics` view. |
| **Verification and evidence** | Which tests, builds, or facts support the result? Routine verification is compressed into high-value evidence. |
| **Context** | What still matters without deserving the first glance? Higher focus makes the model discard more low-value context. |

New results appear automatically and are stored locally in actual completion order. Use the arrow keys to browse older or newer tasks. Focus maps directly to a target prompt compression percentage and reanalyzes the current result; genuine decisions, blockers, major risks, and action-critical information always survive.

### Settings: control capture, reading, and the attention model

<p align="center">
  <img src="docs/images/aperture-settings.svg" width="100%" alt="Aperture settings grouped into capture, reading, and attention-model controls">
</p>

- **Capture:** enable or disable monitoring and switch between Chinese and English. Turns completed while monitoring is off are not backfilled.
- **Reading:** adjust focus, light or dark appearance, and font size. Focus re-distills the current result; appearance and type size change presentation only.
- **Attention model:** configure the OpenRouter API key, model, and custom prompt. After a successful connection test, changes affect future attention scenes only.

## Quick start

### 1. Check the requirements

The current `v0.2.1` preview requires:

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

1. Download `Aperture-v0.2.1-macos-arm64.dmg` or `.zip` from [Releases](https://github.com/mujizi/aperture/releases/latest).
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
3. Through OpenRouter, choose a model from one of its upstream providers and enter your API key.
4. Run the connection test, then enable monitoring.

The key is used only for OpenRouter requests and stored in `~/.aperture/.env` with `0600` permissions. The local service listens only on `127.0.0.1:4317`.

### 4. Use Codex normally

Continue working in Codex as usual. After each completed turn:

- Aperture enters its processing state and presents the new attention scene;
- use the left and right arrow keys to move through older or newer results;
- adjust focus to re-distill the current result at a target compression percentage;
- collapse the panel into a draggable transparent golden pixel-cat icon and click it to expand again;
- copy selected text or the full derived Markdown.

To start Aperture automatically after a restart, add it in **System Settings → General → Login Items**.

## Settings and controls

| Setting | What it does |
| --- | --- |
| Monitoring | Turn capture of completed Codex turns on or off at any time. Turns completed while it is off are not backfilled. |
| Focus | Move left for more detail or right for a higher target information-compression rate. A change re-runs the attention model on the current result without compressing away genuine decisions, blockers, major risks, or action-critical information. |
| Language | Switch between `cn` (Chinese, the default) and `en` (English). UI copy, model prompts, and newly generated attention results use the selected language; custom prompts are stored separately for each language. |
| Appearance | Switch between light and dark interfaces. |
| Font size | Choose a reading size from Compact through Maximum for the floating window. |
| Model configuration | Configure an OpenRouter API key and choose models from various upstream providers. You can favor inexpensive, fast models, refresh the catalog, test the connection, and save the configuration. |
| Prompt | Customize how Aperture selects and organizes attention. The prompt is limited to 4,000 characters and affects future results only. |

## What Aperture helps you do

### Remap model output to human bandwidth

Aperture selects one primary result from the complete final answer, then retains the evidence, risks, and actions that affect judgment. It reconstructs the order of attention instead of mechanically shortening every section.

### Make decisions and blockers visible

A `decision` appears only when a real choice changes what can happen next. A `blocker` appears only when the result is unusable or progress cannot continue. Ordinary suggestions are not promoted into false urgency.

### Match the view to the relationship

Aperture chooses a representation that fits the content:

- `statement` for a standalone conclusion, risk, reason, or action;
- `flow` for a real sequence, causal chain, or process;
- `comparison` for options or before-and-after states with shared dimensions;
- `metrics` when numbers directly explain the result.

### Keep completion history across tasks

Attention scenes are stored locally in actual completion order. Use the arrow keys to review sequential or concurrent tasks without reopening every original conversation.

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

## Future direction

In the future, a person's AI conversation history may become one of their most valuable personal digital assets. It contains more than questions and answers: it records how the person thinks, chooses tools, completes work, and discovers methods that actually succeed.

Aperture aims to make these AI usage records local, automatically organized, and able to evolve over time. They should not remain only a snapshot of one conversation or the trace of one task. They can gradually become durable assets:

- reusable and continuously improved `skills`;
- portable knowledge packs built around projects or domains;
- the user's own preferences, judgment patterns, and ways of working;
- proven, valuable model-use experience that can be invoked again.

A future Aperture should not only explain what happened in the current turn. It should also help people own, organize, and reuse the experience they create with AI. This is a product direction, not a claim that every capability above is already available in the current `v0.2.1` preview.

## Design philosophy

### 1. Human attention is the final bandwidth

Models can generate increasingly long answers, but people should not have to parse every full response after every turn. Aperture exists to decide what deserves attention now, not to generate more content.

### 2. A peripheral companion, not a second workspace

Aperture appears automatically, is readable without navigation, scrolls naturally, and collapses into a bubble. It does not ask users to learn a new workspace or attempt to replace Codex.

### 3. Preserve semantics before choosing a visual form

Flows are used only for real flows, comparisons only for shared dimensions, and metrics only when numbers explain the outcome. Open-ended agent output remains text-first; visuals reveal relationships rather than decorate them.

### 4. Failure must remain visible

If the model is missing, times out, fails, or returns invalid content, Aperture shows an explicit error. It does not disguise failure with rule-based compression or the untouched original answer.

### 5. Focus controls prompt compression

Focus maps directly to a target information-compression percentage and reanalyzes the current result. The model removes low-value context, implementation detail, and repetitive evidence first; genuine decisions, blockers, major risks, and action-critical information are exempt.

### 6. Local-first without pretending to be fully offline

Capture, storage, history, and rendering are local. The attention pass explicitly depends on OpenRouter today. The product should keep this boundary visible so users know which data leaves the machine.

## Repository layout

```text
src/core/                         Event and AttentionScene protocols
src/server/                       Session watcher, storage, model, MCP, and HTTP API
src/web/                          Continuous attention scenes, relationship views, and history
native/ApertureCompanion/         macOS panel, bubble, and menu bar app
plugins/aperture-attention/       Optional hooks, skill, MCP, and runtime
scripts/                          Build, install, and release packaging
```

See [CURRENT_STATE.md](docs/CURRENT_STATE.md) for the current implementation state and known design issues.
