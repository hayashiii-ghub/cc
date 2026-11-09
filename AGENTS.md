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

The `cc-handoff` skill is installed for Codex, Claude Code, and Antigravity (`~/.gemini/config/skills/cc-handoff`).

For shelf handoff/read/open/remove requests, follow [cc-handoff](skills/cc-handoff/SKILL.md). Setup does not start agents or read chats. For a requested app install/update, use `make install-latest` or GitHub Releases; preserve existing data and unrelated installations.

## Development

- `Sources/CC`, `CCCore`, `CCCLI`: app, storage, CLI; matching tests are in `Tests/`. `Tools/CCDemo` is debug-only. Source builds require Xcode and macOS 26+.
- Preserve product `cc:`, CLI `cc-shelf` (`Contents/Helpers/cc-shelf`, installed at `~/.local/bin/cc-shelf`), identity `work.hayashigoto.cc`, store `~/Library/Application Support/cc`, and scheme `cc:`. Do not use the system `cc` compiler as the CLI, add aliases, or restore the `context` namespace.
- `make check` validates app/CLI/installer/packaging scripts; `make run` builds/opens. `swift run cc-shelf --help` inspects CLI options. `swift run cc-demo add-finder-selection` targets the running debug app; releases omit demo triggers.
- `make install-agent-tools` uses `/Applications/cc.app`; set `CC_INSTALL_APP` for another app and `CC_INSTALL_HOME` for isolated tests.
- `site/src/` owns the Bun/TypeScript static site. From `site/`, use Bun 1.4.4: `bun install --frozen-lockfile`, `bun run check`, `bun run test`. `bun run dev` previews; `bun run start` serves the existing build.
- For CF site work use the README's `cc-cf-preview-dev` container (Node 24.22.1 / Bun 1.4.4). Run dependencies/checks/builds there; keep authentication on the Mac. `cf:check` targets domainless `cc-site-preview`; `cf:check:production` targets `cc-site` with only `cc.shigoto.dev`. Both only build/dry-run. Before prebuilt commands inspect the recorded mode, Worker name, and domains; pass the matching mode and explicit `--worker`. cf beta.28 trusts the output's mode when `--mode` is omitted, so omission does not select preview. Keep both config files type-checked and the account independent of mode. Mac commands use `fnm exec --using=24.22.1 cf`; apply domains with `cf workers triggers deploy` only after the intended zone and HTTPS are ready. Preserve unrelated DNS and email records.
- Keep HTML/CSS app illustrations (`site/src/render.ts`) synthetic and distinct from real preview controls. `site/media/cc-og.html` owns the 1200×630 social image: render with local fonts to `site/public/cc/cc-og.png`, confirm PNG bytes/dimensions. Check favicon changes at 16/32px on light/dark backgrounds. Browser changes require desktop/mobile and preview-control checks.
- Do not edit generated `.build/`, `node_modules/`, or `dist/`. Reuse existing scripts. Preserve app/site scope, current icon appearance during naming-only changes, and ignored raw recordings during cleanup.

## Release

`make package` creates `dist/cc-macos.{dmg,zip}` with CLI, installer, skill, and Sparkle; it does not install agent tools. App publication uses the existing tag-triggered GitHub Actions workflow. Keep pre-v0.4.0 Sparkle updates informational because identity/storage migration requires manual installation.

The CF production path serves `https://cc.shigoto.dev` from `cc-site`. Once the approved Cloudflare Builds main trigger is active, main pushes check and publish using the README's commands; other branches do not publish production. Manual deployment remains available. Retain Vercel project `cc`, its deployments, and the saved former DNS records for rollback. To restore Vercel, detach the CF Custom Domain and restore only its saved DNS records in the same zone; do not revert mail or the whole zone. Confirm actual DNS, HTTPS, public assets, and interactions before reporting cutover. Preserve former Sites redirect identity. Verify app installation and agent-tool updates separately.
