# Repository guide

This repository contains the standalone cc: product for macOS.

## Project map

- `Sources/CC/`, `Sources/CCCore/`, and `Sources/CCCLI/`: the macOS app, shared storage, and CLI. Tests are in `Tests/CCTests/` and `Tests/CCCoreTests/`.
- `Package.swift`, `Makefile`, `Assets/`, and `script/`: app build, validation, and packaging.
- `Tools/CCDemo/`: debug-only recording helper.
- `site/`: the Japanese/English product site, built with Next.js/vinext and deployed through a Cloudflare Worker. App previews use HTML/CSS in `site/app/ShelfPreview.tsx`.

Use `cc:` for product copy and `cc-shelf` for the CLI command. Use `CC` for
Swift type/module names and `cc` for paths, IDs, and URL slugs. The package
products are `cc`, `cc-shelf`, and `cc-demo`; the bundled CLI is
`Contents/Helpers/cc-shelf`. The installed command is
`~/.local/bin/cc-shelf`. Do not add a command alias or use the system `cc`
compiler as the shelf CLI.

The app identity is `work.hayashigoto.cc`, its local store is
`~/Library/Application Support/cc`, its deep-link scheme is `cc:`, and
its environment variables use `CC_`. Packages contain `cc.app`, displayed
as `cc:` by macOS, and are named `cc-macos.dmg` and `cc-macos.zip`.

The agent skill is `cc-handoff`, with source in `skills/cc-handoff/SKILL.md`
and installed copies in `~/.codex/skills/cc-handoff` and
`~/.claude/skills/cc-handoff`. Keep protections for unrelated commands,
edited skills, and failed installation rollback. Do not restore the earlier
`context` namespace or add compatibility command aliases. When retiring an old
CLI link, remove only the exact link managed for the selected app.

v0.4.0 is the first release using the `cc` app identity and storage directory.
Earlier versions require a manual installation and separate data/settings
transfer because the bundle identity changed. Keep pre-v0.4.0 updates
informational in the Sparkle feed. Verify actual publication status before reporting a release.

## Validation

- macOS app: `make check`
- website: from `site/`, run `npm run lint` and `npm test`

## Working conventions

- Keep app and site changes scoped unless a cross-product release or brand change is explicitly required.
- Do not edit generated or dependency directories such as `.build/`, `node_modules/`, `dist/`, `.vinext/`, or `.wrangler/`.
- Reuse existing scripts and package commands instead of duplicating build or release logic.
- Back up ignored raw recordings separately before media cleanup. Preserve current icon and site asset appearance during naming-only changes.
