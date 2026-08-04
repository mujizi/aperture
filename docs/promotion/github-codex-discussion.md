Codex can finish several tasks in parallel. I still have one pair of eyes.

I built **Aperture**, an open-source macOS companion that turns completed Codex work into an attention-first view.

Instead of showing another transcript or producing a shorter summary, Aperture identifies:

- the primary outcome
- decisions that genuinely need human input
- blockers and unresolved questions
- evidence and context worth keeping visible

![How Aperture works](https://raw.githubusercontent.com/mujizi/aperture/92a714e65ca13f80fdbce6c3838caf00e55e2a09/docs/images/aperture-workflow.svg)

## What it feels like

Aperture watches completed local Codex turns and automatically opens beside the current workspace. When the result has been reviewed, it collapses into a small draggable bubble.

| Collapsed | Expanded |
| --- | --- |
| ![Aperture collapsed](https://raw.githubusercontent.com/mujizi/aperture/92a714e65ca13f80fdbce6c3838caf00e55e2a09/docs/images/aperture-collapsed.png) | ![Aperture expanded](https://raw.githubusercontent.com/mujizi/aperture/92a714e65ca13f80fdbce6c3838caf00e55e2a09/docs/images/aperture-expanded.jpg) |

The expanded UI gives the most visual weight to the outcome and real decisions. Supporting evidence remains available without competing for attention.

![Aperture attention UI](https://raw.githubusercontent.com/mujizi/aperture/92a714e65ca13f80fdbce6c3838caf00e55e2a09/docs/images/aperture-attention-ui.png)

## More than a summarizer

A summary mainly shortens text.

Aperture tries to answer a different question:

> After an agent finishes, what should the human see first—and what must not disappear?

Focus can change the visual hierarchy without deleting facts. You can also move between previous and newer completed turns.

## How it works

```text
Local Codex session JSONL
        ↓
Session Watcher
        ↓
Cleaned question + complete final answer
        ↓
OpenRouter attention pass
        ↓
Structured AttentionScene
        ↓
macOS companion / Markdown / MCP
```

## UI and settings

Settings let you control the model, attention behavior, automatic appearance, history, and privacy-related options.

![Aperture settings](https://raw.githubusercontent.com/mujizi/aperture/92a714e65ca13f80fdbce6c3838caf00e55e2a09/docs/images/aperture-settings.svg)

## Privacy boundary

Session capture, history, and rendering stay local.

For the attention pass, Aperture sends the cleaned question and complete final answer to the configured OpenRouter model. Raw tool calls and tool output are not sent.

## Current preview requirements

- Apple Silicon and macOS 13+
- Node.js 22+
- an OpenRouter API key and a structured-output-capable model
- the preview build is ad-hoc signed and not Apple-notarized yet

## Try Aperture

Repository: https://github.com/mujizi/aperture

I would especially value feedback from people running multiple Codex tasks:

1. Is the term **attention layer** understandable, or would you describe it differently?
2. Which information do you need to see first when an agent finishes?
3. Would you prefer this as a floating companion, a menu-bar surface, or both?
