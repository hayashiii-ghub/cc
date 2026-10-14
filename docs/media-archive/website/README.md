# Website media archive

These files preserve earlier Context and cc: website visuals. They previously
lived in `site/public/context/` and are no longer referenced by the current
landing page, which uses HTML/CSS illustrations in `site/app/ShelfPreview.tsx`.
Keeping them outside `site/public/` excludes them from the site's public assets.

## Former names

Paths in the first column are relative to the former `site/public/context/`
directory. Paths in the second column are relative to this archive directory.

| Former filename | Archived filename |
| --- | --- |
| `context-hero.mp4` | `context-hero.mp4` |
| `context-hero.webm` | `context-hero.webm` |
| `context-hero-poster.webp` | `context-hero-poster.webp` |
| `context-capture.mp4` | `context-capture.mp4` |
| `context-capture.webm` | `context-capture.webm` |
| `context-capture-poster.webp` | `context-capture-poster.webp` |
| `context-hold.mp4` | `context-hold.mp4` |
| `context-hold.webm` | `context-hold.webm` |
| `context-hold-poster.webp` | `context-hold-poster.webp` |
| `context-place.mp4` | `context-place.mp4` |
| `context-place.webm` | `context-place.webm` |
| `context-place-poster.webp` | `context-place-poster.webp` |
| `context-hero.webp` | `context-menubar-shelf.webp` |
| `context-capture.webp` | `context-menubar-shelf.webp` |
| `context-hold.webp` | `context-menubar-shelf.webp` |
| `context-place.webp` | `context-place.webp` |
| `context-current-icon.png` | `context-current-icon.png` |
| `context-display-modes.webp` | `context-display-modes.webp` |

The three Menu Bar WebP files were byte-for-byte identical, so one copy is kept
as `context-menubar-shelf.webp`. Its SHA-256 is
`73b2ddb2e47fe5854faccc5b7f05f5d59740b5d2652848d7770bf844920c687f`.
The other files retain their original names and bytes.

The original montage source remains in `videos/context-hero-montage/`, and the
PNG capture sources remain in `site/media/`. The current social-image source is
`site/media/context-og.html`; its generated PNG, the cc: mark, favicon, and fonts
remain under `site/public/context/`.
