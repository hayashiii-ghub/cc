# cc: capture kit

The current Japanese/English website uses HTML/CSS app illustrations in
[`ShelfPreview.tsx`](../../site/app/ShelfPreview.tsx), with sample items rather
than screenshots or videos. This recording kit is retained for future demos
and historical reference; archived footage may show the former Context name
and interface.

This folder keeps the small, reusable pieces needed to record product demos without preserving a dedicated recording desktop.

Previous compressed website videos and captures are preserved in
[`../media-archive/website/`](../media-archive/website/README.md), with a mapping
of their former filenames. They are not served by the current site. The editable
montage and its normalized clips remain under `../../videos/context-hero-montage/`.
Raw recordings remain local under that project's `assets/source/` and are
intentionally excluded from Git; keep those originals separately backed up.

## Contents

- `context-demo-background.png` and `.svg`: the neutral recording wallpaper at 3024 × 1964.
- `demo-files/`: fictional files that are safe to show in public recordings.
- `local-drop-target.html`: an offline visual drop target for handoff shots. It is not a product verification tool.
- `scripts/`: coordinate-specific macOS helpers used during the original recording session.

## Before recording

1. Create or reuse a clean macOS Space with no unrelated or private windows.
2. Set `context-demo-background.png` as the wallpaper for that Space.
3. In System Settings → Desktop & Dock, move the Dock to the **bottom** and enable **Automatically hide and show the Dock**.
4. Hide notifications and close unrelated apps, Finder windows, and desktop items.
5. Use the Menu Bar shelf as the default product presentation. Enable Notch Island only for the demo that specifically introduces it.
6. Copy `demo-files/` to a temporary folder and record with those fictional files only.

## Recording and export

- The original recordings used a 3024 × 1964 display at 30 fps.
- The archived video workflow normalized to 1920 × 1080 and delivered 1600 × 900 MP4, WebM, and poster assets.
- If a future page uses these videos, keep the full 16:9 frame on narrow screens and scale it without cropping.
- Review every take for notifications, private content, unexpected Finder windows, and cursor mistakes before publishing.

The Swift helpers post synthetic pointer and keyboard events. Their coordinates were tuned for a 3024 × 1964 display and may not match another setup. Inspect them before use, and grant Accessibility or Screen Recording access only when macOS requests it for the tool you intentionally run.

`local-drop-target.html` runs locally and does not make network requests. Its visual attached state is useful for composition, but browser drop acceptance was not used to verify cc: behavior.

## After recording

Return the Mac to the state that existed before this recording setup:

1. Move the Dock back to the **right** and keep **Automatically hide and show the Dock** enabled.
2. Keep recent applications hidden in the Dock.
3. Restore the built-in **Macintosh** wallpaper.
4. Restore Focus and notification settings to their previous values.
5. Close the clean recording Space after confirming it contains no needed windows.
6. Remove temporary copies of the demo files, background, previews, caches, and intermediate exports.

## Recording cautions

- Keep only the intended `cc Demo` Finder window in frame.
- Do not drag shelf content back into the same `cc Demo` folder if Finder asks to replace `Brand assets`.
- Avoid touching the physical top edge while dragging to Notch Island; macOS may open Mission Control.
- Treat the scripts as optional capture helpers, not automated product tests.
