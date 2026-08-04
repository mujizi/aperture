# Aperture launch thread for X

## Post 1

LLMs can produce work faster than humans can review it.

I built Aperture: an open-source macOS attention layer between LLM output bandwidth and human input bandwidth.

It turns completed Codex tasks into outcomes, decisions, blockers, and evidence. 🧵

Attach: `docs/images/aperture-attention-ui.png`

## Post 2

A summary makes an answer shorter.

Aperture asks a different question: after an agent finishes, what should the human see first—and what must not disappear?

Focus changes visual weight without deleting facts.

Attach: `docs/promotion/aperture-workflow.svg.png`

## Post 3

It watches completed local Codex turns, opens beside your workspace, and collapses into a draggable bubble when reviewed.

You can move between completed turns without reopening every transcript.

Attach both:

- `docs/images/aperture-collapsed.png`
- `docs/images/aperture-expanded.jpg`

## Post 4

Capture, history, and rendering stay on your Mac.

For the attention pass, the cleaned question + final answer go to your configured OpenRouter model. Raw tool calls and tool output are not sent.

Attach: `docs/promotion/aperture-settings.svg.png`

## Post 5

Early preview: Apple Silicon, macOS 13+, Node.js 22+, and an OpenRouter key.

Open source: https://github.com/mujizi/aperture

What should an agent-completion surface show you first: the outcome, decisions, blockers, or evidence?
