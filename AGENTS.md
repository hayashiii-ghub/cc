# Repository guide

This repository contains the standalone cc: product for macOS.

## Project map

- `Sources/Context/` and `Tests/ContextTests/`: the macOS app and its Swift tests. `Package.swift`, the root `Makefile`, `Assets/`, and `script/` belong to the app.
- `site/`: the standalone Japanese/English product site, built with Next.js/vinext and deployed through a Cloudflare Worker. App previews use HTML/CSS in `site/app/ShelfPreview.tsx`.
- `videos/context-hero-montage/`: the archived, editable HyperFrames source for the previous website hero. The current site does not use it. Follow its nested `AGENTS.md` when working there.
- `docs/capture-kit/`: reusable recording backgrounds, fictional demo files, and capture helpers.
- `docs/media-archive/website/`: previous website delivery assets and their original-name mapping; these are not served by the current site.

User-facing product copy should use `cc:`.
Keep the existing `Context` source/product names, bundle identifier, data directory,
`context` CLI, `context-handoff` skill name, and release URLs stable for compatibility.
Release packages contain `cc.app`, displayed as `cc:` by macOS. The installer
also accepts legacy `Context.app` packages and preserves a migration backup
when replacing an existing legacy installation.

## Validation

- macOS app: `make check`
- website: from `site/`, run `npm run lint` and `npm test`
- archived hero composition, when editing it: from `videos/context-hero-montage/`, run `npm run check`

## Working conventions

- Keep app and site changes scoped unless a cross-product release or brand change is explicitly required.
- Do not edit generated or dependency directories such as `.build/`, `node_modules/`, `dist/`, `.vinext/`, or `.wrangler/`.
- Reuse existing scripts and package commands instead of duplicating build or release logic.
- Preserve the archived composition, its `assets/segments/` inputs, and local raw recordings under `assets/source/`. Raw recordings are ignored by Git and require a separate backup before any media cleanup.
