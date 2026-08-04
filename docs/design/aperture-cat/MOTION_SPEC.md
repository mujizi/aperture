# Aperture pixel cat — compact icon design

## Static mark

- Keep the existing aperture mark in the expanded 29×29 header.
- Replace only the collapsed 64×64 bubble artwork with the golden pixel cat.
- Render the mascot at approximately 44×43 px, offset slightly left and down.
  This preserves the top-right unread-count area.
- The cat holds the existing aperture visual language over one eye; there is no
  coin, medallion, or outer circular frame.
- Use nearest-neighbor scaling. Never blur or interpolate the logical pixels.

## Motion loop

Total duration: 2.8 s. Most of the loop is intentionally still.

| Time | State | Motion |
| --- | --- | --- |
| 0–1000 ms | Rest | No movement. |
| 1000–1200 ms | Notice | Cat moves down by at most 1 px; lens rotates to −6°. |
| 1200–1500 ms | Focus | Lens rotates through +6°; aperture opening contracts from 3 px to 1 px. |
| 1500–1600 ms | Blink | Visible eye closes for 100 ms. |
| 1600–1900 ms | Confirm | Aperture reopens; one tiny 1 px lens sparkle appears briefly. |
| 1900–2800 ms | Settle | Return to the exact rest pose and hold. |

## Behavior

- Play immediately when the companion collapses or a new unread result arrives.
- While collapsed and connected, repeat the observation action at a randomized
  6.5–8 second start-to-start interval; keep the icon still between actions.
- A new unread result resets the idle interval so two loops never overlap.
- Dragging, clicking, expanding, or disconnecting cancels the current loop.
- With Reduce Motion enabled, skip translation and rotation; use only the single
  blink or keep the icon completely still.

## Production note

For the Swift implementation, draw the cat and the aperture disc as separate
pixel-aligned layers. Animate only integer-point translation and the lens layer;
keep filtering set to nearest-neighbor so the mascot remains crisp on Retina and
non-Retina displays.
