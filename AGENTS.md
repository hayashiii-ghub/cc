# Repository guide

This repository contains the standalone cc: product for macOS.

## Agent setup and updates

For a setup request, locate the installed `cc.app` and use its bundled installer.
The commands below assume `/Applications`. For another location, use its script
path and set `CC_INSTALL_APP` to that app’s absolute path on each invocation.

```sh
"/Applications/cc.app/Contents/Resources/install_agent_tools.sh" --check
"/Applications/cc.app/Contents/Resources/install_agent_tools.sh" --print-plan
"/Applications/cc.app/Contents/Resources/install_agent_tools.sh"
```

`--check` is read-only and prints JSON. Exit 0 means inspection completed, not
that tools are current: inspect `status`. Invalid checks return `unknown` and a
nonzero exit. Run the final command when setup or an update is requested.
It installs the CLI link and both skills listed below without network access
or shell configuration changes. Rerun after app updates to refresh unchanged
managed skills; app updates alone do not refresh them. Settings reports status.

For handoff and shelf reading, opening, or removal requests, follow
[cc-handoff](skills/cc-handoff/SKILL.md); it covers CLI discovery, text, JSON,
permissions, and errors. Installing it does not start agents or read chats.

For a requested app installation or update, use `make install-latest` or the
latest GitHub release. Preserve existing data and unrelated installations.

## Project map

- `Sources/CC/`, `Sources/CCCore/`, and `Sources/CCCLI/`: the macOS app, shared storage, and CLI. Tests are in `Tests/CCTests/`, `Tests/CCCoreTests/`, and `Tests/CCCLITests/`.
- `Package.swift`, `Makefile`, `Assets/`, and `script/`: app build, validation, and packaging.
- `Tools/CCDemo/`: debug-only recording helper.
- `site/`: the Japanese/English static product site, built with Bun and TypeScript. Source is in `site/src/`, build output is `site/dist/`, and app previews use HTML/CSS in `site/src/render.ts`.

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

## Development and validation

Source builds require Xcode and macOS 26 or later.

- App: `make run` builds and opens it; `make check` validates the app, CLI, installer, and packaging scripts.
- Distribution: `make package` creates `dist/cc-macos.dmg` and `dist/cc-macos.zip`, including the CLI, installer, skill, and Sparkle. It does not install agent tools.
- Agent installer: `make install-agent-tools` uses `/Applications/cc.app`; set `CC_INSTALL_APP` for another copy and `CC_INSTALL_HOME` for isolated tests.
- CLI: `swift run cc-shelf --help`. `swift run cc-demo add-finder-selection` triggers the running debug app; release builds omit the helper and its triggers.
- Site: from `site/`, use Bun 1.4.2 and run `bun install --frozen-lockfile`, then `bun run dev` for preview or `bun run check` and `bun run test` for validation. `bun run start` serves the existing `dist/` build.

App publication uses the existing tag-triggered GitHub Actions release workflow.
Site publication uses the Vercel `cc` project, with `site/` as its root and
`dist/` as build output. Pull requests get previews; `main` publishes
`https://cc.shigoto.dev`. Keep the former Sites identity for old-URL redirects.
Verify public assets separately from source checks and local installation.

## Working conventions

- Keep human-facing guidance in `README.md` and agent procedures in `AGENTS.md`, both minimal. Ask before adding other documentation; retain required licenses and the distributable skill.
- Keep app and site changes scoped unless a cross-product release or brand change is explicitly required.
- Do not edit generated or dependency directories such as `.build/`, `node_modules/`, or `dist/`.
- Reuse existing scripts and package commands instead of duplicating build or release logic.
- Back up ignored raw recordings separately before media cleanup. Preserve current icon and site asset appearance during naming-only changes.
