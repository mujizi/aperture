---
name: attention-review
description: Use when the user asks to read or show the latest Aperture result.
---

# Aperture Attention Review

Use Aperture as an attention-compression layer.

## Read a review

1. Call `aperture_get_review`.
2. Present `resultMarkdown` directly, without summarizing or expanding it again.
3. When a visual scan will help, call `aperture_render_review`.

## Quality bar

- Do not invent facts or add a second interpretation layer.
- Preserve the amount of detail selected by the user's focus setting.
