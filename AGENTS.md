# cc:

User guidance belongs in `README.md`; repository procedures belong here. Keep both minimal; ask before adding other documentation. Retain licenses and the functional `skills/cc-handoff/SKILL.md`. PR descriptions state the change and validation.

## Agent setup

Locate the installed `cc.app` and use its bundled installer. These commands assume `/Applications`; for another location, use its script path and set `CC_INSTALL_APP` to that app's absolute path:

```sh
"/Applications/cc.app/Contents/Resources/install_agent_tools.sh" --check
"/Applications/cc.app/Contents/Resources/install_agent_tools.sh" --print-plan
"/Applications/cc.app/Contents/Resources/install_agent_tools.sh"
```

`--check` is read-only: inspect JSON `status`; exit 0 alone does not mean current. Failed/invalid inspection means unknown. Run the final command only for requested setup/update. It installs CLI/skills without network or shell changes; rerun after app updates. Preserve edited skills, unrelated commands/settings, and rollback on failure. Remove only links owned by the selected app.

For shelf handoff/read/open/remove requests, follow [cc-handoff](skills/cc-handoff/SKILL.md). Setup does not start agents or read chats. For a requested app install/update, use `make install-latest` or GitHub Releases; preserve existing data and unrelated installations.

## Development

- `Sources/CC`, `CCCore`, `CCCLI`: app, storage, CLI; matching tests are in `Tests/`. `Tools/CCDemo` is debug-only. Source builds require Xcode and macOS 26+.
- Preserve product `cc:`, CLI `cc-shelf` (`Contents/Helpers/cc-shelf`, installed at `~/.local/bin/cc-shelf`), identity `work.hayashigoto.cc`, store `~/Library/Application Support/cc`, and scheme `cc:`. Do not use the system `cc` compiler as the CLI, add aliases, or restore the `context` namespace.
- `make check` validates app/CLI/installer/packaging scripts; `make run` builds/opens. `swift run cc-shelf --help` inspects CLI options. `swift run cc-demo add-finder-selection` targets the running debug app; releases omit demo triggers.
- `make install-agent-tools` uses `/Applications/cc.app`; set `CC_INSTALL_APP` for another app and `CC_INSTALL_HOME` for isolated tests.
- `site/src/` owns the Bun/TypeScript static site. From `site/`, use Bun 1.4.2: `bun install --frozen-lockfile`, `bun run check`, `bun run test`. `bun run dev` previews; `bun run start` serves the existing build.
- Keep HTML/CSS app illustrations (`site/src/render.ts`) synthetic and distinct from real preview controls. `site/media/cc-og.html` owns the 1200×630 social image: render with local fonts to `site/public/cc/cc-og.png`, confirm PNG bytes/dimensions. Check favicon changes at 16/32px on light/dark backgrounds. Browser changes require desktop/mobile and preview-control checks.
- Do not edit generated `.build/`, `node_modules/`, or `dist/`. Reuse existing scripts. Preserve app/site scope, current icon appearance during naming-only changes, and ignored raw recordings during cleanup.

## Release

`make package` creates `dist/cc-macos.{dmg,zip}` with CLI, installer, skill, and Sparkle; it does not install agent tools. App publication uses the existing tag-triggered GitHub Actions workflow. Keep pre-v0.4.0 Sparkle updates informational because identity/storage migration requires manual installation.

Vercel project `cc` builds `site/` to `dist/`; PRs get previews and `main` publishes `https://cc.shigoto.dev`. Preserve former Sites redirect identity. Verify public assets, local installation, and agent-tool updates separately before reporting completion.
