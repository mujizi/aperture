Disclosure: I built this.

I often have several Codex tasks running, but when they finish I still need to reopen each thread and work out what actually changed, what needs a decision, and what is still blocked.

So I built **Aperture**, a small open-source macOS companion for completed Codex work.

It watches completed local Codex turns and converts the final result into an attention-first view:

- the outcome is shown first
- real decisions and blockers stay prominent
- supporting evidence remains visible without dominating the screen
- the window can collapse into a draggable bubble after review
- previous and newer completed turns remain easy to revisit

Screenshot: https://raw.githubusercontent.com/mujizi/aperture/92a714e65ca13f80fdbce6c3838caf00e55e2a09/docs/images/aperture-attention-ui.png

The distinction I am experimenting with is **attention layer vs. summarizer**.

A summary mostly makes the answer shorter. Aperture tries to decide what the human should see first, what must not disappear, and what can recede into context.

The current flow is:

```text
local Codex session JSONL
→ session watcher
→ cleaned question + complete final answer
→ OpenRouter attention pass
→ structured AttentionScene
→ macOS companion
```

Capture, history, and rendering stay local. The cleaned question and complete final answer are sent to the OpenRouter model you configure; raw tool calls and tool output are not sent.

The preview currently requires Apple Silicon, macOS 13+, Node.js 22+, and an OpenRouter key. It is ad-hoc signed and not Apple-notarized yet.

GitHub: https://github.com/mujizi/aperture

I would really value blunt feedback from people who use multiple Codex tasks:

1. Does “attention layer” make sense, or is there a clearer name?
2. What do you personally look for first when a task finishes?
3. Would you want this as a floating window, menu-bar app, or both?
