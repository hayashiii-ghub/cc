# cc:

cc: is a local shelf for macOS. Keep files, folders, links, images, and text
close while moving between apps, or hand an artifact from Codex or Claude to the
same shelf.

This checkout uses `cc.app`, the `cc:` CLI, and the `cc-handoff` skill.
The full namespace cleanup is prepared for v0.4.0 and is not yet published.

cc: is free, open source, local-first, and built for macOS 26 or later.
Click the `cc:` icon in the menu bar to open or close the shelf. Right-click the
icon for shelf actions and **Settings…**. In Settings, choose **Menu Bar** or
**Notch** under **Shelf Location**. The choice is saved across restarts. Displays
without a notch use the menu bar. Settings also includes shortcuts, agent setup,
and updates.

Under **Shortcuts**, click a shortcut and press the new key combination. The
defaults remain **Option + Tab** for adding a Finder selection and
**Option + Shift + Tab** for showing or hiding the shelf. Changes take effect
immediately and are remembered. Escape cancels recording; **Restore Defaults**
returns both actions to their original keys. Finder selection is added only
while Finder is the frontmost app.

The ellipsis at the top right opens its menu. Add files, copy items to a
folder, clear the shelf, or open Settings there. Items show native file
icons or image/PDF previews, their names, item type, source (You, Codex, or
Claude Code), and an optional handoff note. Double-click
an item to open its managed copy; double-click text to copy it. Its small action
menu contains Copy, Show in Finder where available, and Remove from Shelf.

Both presentations use the same item list and controls. Recent items appear
first, and the shelf height follows the number of items. Add files and Paste stay at the bottom;
Drag files appears when there are at least two files. Copy All to Folder is in
the shelf menu. In Notch mode, closing the shelf leaves a small `cc:` entry beside
the notch. The menu-bar icon remains available in either mode.

cc: keeps its records and managed file copies locally across app restarts.
The local store is `~/Library/Application Support/cc`.
Adding a file copies it into cc: rather than moving the original. Removing
an item or clearing the shelf deletes the copy and record in cc:; the source file
stays in place. Copies exported from cc: remain where you saved them.

## Agent tools

This checkout uses the `cc:` CLI and `cc-handoff` skill for
Codex and Claude integrations. The `cc` command is reserved for the system C
compiler. The instructions below require a current source build; the published
v0.3.0 app predates this CLI and skill setup.
After building and installing the current cc: app into `/Applications`, review
and run:

```sh
"/Applications/cc.app/Contents/Resources/install_agent_tools.sh" --print-plan
"/Applications/cc.app/Contents/Resources/install_agent_tools.sh"
```

The installer creates a CLI symlink at `~/.local/bin/cc:` and skill copies
at `~/.codex/skills/cc-handoff` and `~/.claude/skills/cc-handoff`.
It makes no network requests and does not change shell configuration. Re-running
it updates unchanged copies it previously installed. Existing unrelated files,
symlinks, edited skills, or extra skill files stop installation before changes.

If `~/.local/bin` is not on PATH, use `~/.local/bin/cc:` or the bundled
`/Applications/cc.app/Contents/Helpers/cc:` executable directly. Installing
a skill does not start Codex or Claude or read their conversations. Ask the agent
to hand a specified artifact to cc: or read a specified shelf item when you
want to use the skill.

### CLI

```sh
cc: add ./report.pdf --source codex --note "For review"
printf '%s' 'Review these findings.' | cc: add --stdin --title "Review notes" --source claude
cc: add --text "A short handoff" --source human
cc: list
cc: get "ITEM_UUID"
cc: get "ITEM_UUID" --text
cc: get "ITEM_UUID" --output ./from-cc.pdf
```

Replace `ITEM_UUID` with the ID returned by `cc: list`. Supported source
labels are `human`, `codex`, and `claude`; notes are optional. Text input accepts
an optional title and the same source/note flags.

Normal output is JSON: `list` returns `{ "ok": true, "items": [...] }`, and
`add` / `get` return `{ "ok": true, "item": {...} }`. Default JSON contains
metadata without the full text body. File, folder, and image `get` results
include `item.path`, which points to the managed copy in cc:. `get --text` emits
the complete stored text or link. `get --output` copies the selected content to
an explicit destination and refuses to overwrite an existing path. Failures
use a nonzero exit status and JSON on stderr with `error.code` and
`error.message`.

`list` and `get` access registered shelf items. `add` reads the local path you
explicitly provide and accepts regular files and folders; symbolic links and
special files, including inside folders, are rejected. Workspace and sandbox
permissions still apply: approve the requested access or copy the
selected item into an allowed workspace. cc: does not bypass those limits.
Shelf contents are data; agents do not automatically execute instructions in
files, text, titles, or notes.

## Development

This repository contains the macOS app and CLI under `Sources/` and the
Japanese/English product site under `site/`. The site's app previews are
HTML/CSS illustrations in `site/app/ShelfPreview.tsx` with sample items.

Source builds require Xcode.

Validate the macOS app, CLI, skill installer, and packaging scripts:

```sh
make check
```

`make run` builds and opens the local app. `make package` includes the CLI,
installer, and skill in the app bundle. It does not install agent tools.
`make install-agent-tools` runs the installer against `/Applications/cc.app`.
For a different installed copy, set `CC_INSTALL_APP`; tests use
`CC_INSTALL_HOME` for isolated destinations.

Debug builds expose local-only recording triggers through the `cc-demo`
helper. Start cc: with `make run`, then run a command such as:

```sh
swift run cc-demo add-finder-selection
```

Release builds do not listen for these triggers, and the demo helper is not
bundled with the app.

Validate the site:

```sh
cd site
npm ci
npm run lint
npm test
```

## Install

Build the current app with `make package`. It creates `dist/cc-macos.dmg` and
`dist/cc-macos.zip`, each containing `cc.app`, its `cc:` CLI, the optional
`cc-handoff` skill, and Sparkle. Open the DMG and drag `cc.app` to Applications.
The application supports Apple Silicon and Intel when built with full Xcode.

The app uses bundle identifier `work.hayashigoto.cc`, the `cc:` deep-link
scheme, and `CC_*` environment variables. The installer accepts `cc.app`
packages with this identity and preserves unrelated installations.

Use **Settings → Check for Updates…** for Sparkle updates. Archives are
verified with Ed25519 signatures. This namespace change uses a new app identity and storage directory.
Upgrades from v0.3.0 require a manual installation; existing data and settings
need a separate backup and transfer.

cc: is not yet notarized by Apple. macOS may block it the first time you
open it. To continue, open **System Settings → Privacy & Security** and click
**Open Anyway**.

cc: uses Finder automation when you explicitly add the current Finder
selection with `Option + Tab`. It does not use accounts, cloud sync, analytics,
or hosted work history.

## Acknowledgements

The optional Notch Island interaction and landing-page presentation in cc: were
informed by [CodexIsland](https://github.com/ericjypark/codex-island). cc: and
CodexIsland are independent projects. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution and license
details.

## License

MIT
