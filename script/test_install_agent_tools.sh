#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/app_bundle.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/context-agent-tools-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
TEST_APP="$TMP_ROOT/Applications/cc.app"
mkdir -p "$TEST_APP/Contents/Helpers" "$TEST_APP/Contents/Resources/skills/context-handoff"
printf '#!/bin/sh\nexit 0\n' >"$TEST_APP/Contents/Helpers/context"
chmod +x "$TEST_APP/Contents/Helpers/context"
context_write_info_plist "$TEST_APP/Contents/Info.plist" 1.2.3
cp "$ROOT_DIR/skills/context-handoff/SKILL.md" "$TEST_APP/Contents/Resources/skills/context-handoff/SKILL.md"

run_installer() {
  local test_home="$1"
  shift
  CONTEXT_INSTALL_HOME="$test_home" CONTEXT_INSTALL_APP="$TEST_APP" \
    "$ROOT_DIR/script/install_agent_tools.sh" "$@" >"$TMP_ROOT/install.log" 2>"$TMP_ROOT/install-error.log"
}

expect_rejection() {
  if run_installer "$1"; then
    echo "Expected installer to preserve a conflicting destination" >&2
    exit 1
  fi
}

TEST_HOME="$TMP_ROOT/clean home"
mkdir "$TEST_HOME"
run_installer "$TEST_HOME" --print-plan
test ! -e "$TEST_HOME/.local"
test ! -e "$TEST_HOME/.codex"
test ! -e "$TEST_HOME/.claude"
run_installer "$TEST_HOME"
test "$(readlink "$TEST_HOME/.local/bin/context")" = "$TEST_APP/Contents/Helpers/context"
for agent in .codex .claude; do
  cmp -s "$TEST_APP/Contents/Resources/skills/context-handoff/SKILL.md" "$TEST_HOME/$agent/skills/context-handoff/SKILL.md"
  test -f "$TEST_HOME/$agent/skills/context-handoff/.context-install-manifest"
done
CLI_INODE="$(stat -f '%i' "$TEST_HOME/.local/bin/context")"
SKILL_INODE="$(stat -f '%i' "$TEST_HOME/.codex/skills/context-handoff/SKILL.md")"
run_installer "$TEST_HOME"
test "$(stat -f '%i' "$TEST_HOME/.local/bin/context")" = "$CLI_INODE"
test "$(stat -f '%i' "$TEST_HOME/.codex/skills/context-handoff/SKILL.md")" = "$SKILL_INODE"

printf '\nUpdated bundled handoff instructions.\n' >>"$TEST_APP/Contents/Resources/skills/context-handoff/SKILL.md"
run_installer "$TEST_HOME"
for agent in .codex .claude; do
  cmp -s "$TEST_APP/Contents/Resources/skills/context-handoff/SKILL.md" "$TEST_HOME/$agent/skills/context-handoff/SKILL.md"
done

printf '\nMy custom instruction.\n' >>"$TEST_HOME/.codex/skills/context-handoff/SKILL.md"
cp "$TEST_HOME/.codex/skills/context-handoff/SKILL.md" "$TMP_ROOT/edited-skill.md"
expect_rejection "$TEST_HOME"
cmp -s "$TMP_ROOT/edited-skill.md" "$TEST_HOME/.codex/skills/context-handoff/SKILL.md"
cmp -s "$TEST_APP/Contents/Resources/skills/context-handoff/SKILL.md" "$TEST_HOME/.claude/skills/context-handoff/SKILL.md"
test "$(stat -f '%i' "$TEST_HOME/.local/bin/context")" = "$CLI_INODE"

FILE_HOME="$TMP_ROOT/existing-cli-file"
mkdir -p "$FILE_HOME/.local/bin"
printf 'my existing command\n' >"$FILE_HOME/.local/bin/context"
expect_rejection "$FILE_HOME"
test "$(cat "$FILE_HOME/.local/bin/context")" = 'my existing command'
test ! -e "$FILE_HOME/.codex"
test ! -e "$FILE_HOME/.claude"

LINK_HOME="$TMP_ROOT/existing-cli-link"
mkdir -p "$LINK_HOME/.local/bin"
ln -s /usr/bin/true "$LINK_HOME/.local/bin/context"
expect_rejection "$LINK_HOME"
test "$(readlink "$LINK_HOME/.local/bin/context")" = /usr/bin/true
test ! -e "$LINK_HOME/.codex"

SKILL_HOME="$TMP_ROOT/existing-skill"
mkdir -p "$SKILL_HOME/.claude/skills/context-handoff"
printf 'my skill\n' >"$SKILL_HOME/.claude/skills/context-handoff/SKILL.md"
expect_rejection "$SKILL_HOME"
test "$(cat "$SKILL_HOME/.claude/skills/context-handoff/SKILL.md")" = 'my skill'
test ! -e "$SKILL_HOME/.local"
test ! -e "$SKILL_HOME/.codex"

EXTRA_HOME="$TMP_ROOT/extra-skill-file"
mkdir "$EXTRA_HOME"
run_installer "$EXTRA_HOME"
printf 'keep this file\n' >"$EXTRA_HOME/.codex/skills/context-handoff/notes.txt"
expect_rejection "$EXTRA_HOME"
test "$(cat "$EXTRA_HOME/.codex/skills/context-handoff/notes.txt")" = 'keep this file'

PARENT_HOME="$TMP_ROOT/symlink-parent"
mkdir "$PARENT_HOME" "$TMP_ROOT/external-skills"
ln -s "$TMP_ROOT/external-skills" "$PARENT_HOME/.codex"
expect_rejection "$PARENT_HOME"
test -z "$(find "$TMP_ROOT/external-skills" -mindepth 1 -print -quit)"
test ! -e "$PARENT_HOME/.local"

ROLLBACK_HOME="$TMP_ROOT/rollback-home"
mkdir "$ROLLBACK_HOME" "$TMP_ROOT/fakebin"
cat >"$TMP_ROOT/fakebin/mv" <<'MV'
#!/bin/bash
if [[ "$#" == 2 && "$2" == "$CONTEXT_TEST_FAIL_DEST" && ! -e "$CONTEXT_TEST_FAIL_ONCE" ]]; then
  : >"$CONTEXT_TEST_FAIL_ONCE"
  exit 1
fi
exec /bin/mv "$@"
MV
chmod +x "$TMP_ROOT/fakebin/mv"
export CONTEXT_TEST_FAIL_DEST="$ROLLBACK_HOME/.claude/skills/context-handoff"
export CONTEXT_TEST_FAIL_ONCE="$TMP_ROOT/failed-once"
ORIGINAL_TEST_PATH="$PATH"
PATH="$TMP_ROOT/fakebin:$PATH"
expect_rejection "$ROLLBACK_HOME"
PATH="$ORIGINAL_TEST_PATH"
test ! -e "$ROLLBACK_HOME/.local"
test ! -e "$ROLLBACK_HOME/.codex"
test ! -e "$ROLLBACK_HOME/.claude"
test -z "$(find "$ROLLBACK_HOME" -mindepth 1 -print -quit)"

run_installer "$ROLLBACK_HOME"
cp "$ROLLBACK_HOME/.codex/skills/context-handoff/SKILL.md" "$TMP_ROOT/before-upgrade.md"
printf '\nAnother bundled update.\n' >>"$TEST_APP/Contents/Resources/skills/context-handoff/SKILL.md"
rm "$CONTEXT_TEST_FAIL_ONCE"
PATH="$TMP_ROOT/fakebin:$PATH"
expect_rejection "$ROLLBACK_HOME"
PATH="$ORIGINAL_TEST_PATH"
for agent in .codex .claude; do
  cmp -s "$TMP_ROOT/before-upgrade.md" "$ROLLBACK_HOME/$agent/skills/context-handoff/SKILL.md"
done
test "$(readlink "$ROLLBACK_HOME/.local/bin/context")" = "$TEST_APP/Contents/Helpers/context"
test -z "$(find "$ROLLBACK_HOME" -maxdepth 1 -name '.context-agent-tools.*' -print -quit)"

MIGRATION_HOME="$TMP_ROOT/legacy-cli-home"
LEGACY_CLI="$(dirname "$TEST_APP")/Context.app/Contents/Helpers/context"
mkdir -p "$MIGRATION_HOME/.local/bin"
ln -s "$LEGACY_CLI" "$MIGRATION_HOME/.local/bin/context"
run_installer "$MIGRATION_HOME" --print-plan
test "$(readlink "$MIGRATION_HOME/.local/bin/context")" = "$LEGACY_CLI"
run_installer "$MIGRATION_HOME"
test "$(readlink "$MIGRATION_HOME/.local/bin/context")" = "$TEST_APP/Contents/Helpers/context"

# An edited skill must reject the entire agent-tools update, including link migration.
EDITED_MIGRATION_HOME="$TMP_ROOT/edited-migration-home"
mkdir "$EDITED_MIGRATION_HOME"
run_installer "$EDITED_MIGRATION_HOME"
rm "$EDITED_MIGRATION_HOME/.local/bin/context"
ln -s "$LEGACY_CLI" "$EDITED_MIGRATION_HOME/.local/bin/context"
printf '\nMy custom migration instruction.\n' >>"$EDITED_MIGRATION_HOME/.codex/skills/context-handoff/SKILL.md"
cp "$EDITED_MIGRATION_HOME/.codex/skills/context-handoff/SKILL.md" "$TMP_ROOT/edited-migration-skill.md"
expect_rejection "$EDITED_MIGRATION_HOME"
test "$(readlink "$EDITED_MIGRATION_HOME/.local/bin/context")" = "$LEGACY_CLI"
cmp -s "$TMP_ROOT/edited-migration-skill.md" "$EDITED_MIGRATION_HOME/.codex/skills/context-handoff/SKILL.md"

# A failed link replacement restores both the legacy link and any upgraded skills.
rm "$MIGRATION_HOME/.local/bin/context"
ln -s "$LEGACY_CLI" "$MIGRATION_HOME/.local/bin/context"
cp "$MIGRATION_HOME/.codex/skills/context-handoff/SKILL.md" "$TMP_ROOT/before-cli-migration.md"
printf '\nCLI migration update.\n' >>"$TEST_APP/Contents/Resources/skills/context-handoff/SKILL.md"
export CONTEXT_TEST_FAIL_DEST="$MIGRATION_HOME/.local/bin/context"
rm -f "$CONTEXT_TEST_FAIL_ONCE"
PATH="$TMP_ROOT/fakebin:$PATH"
expect_rejection "$MIGRATION_HOME"
PATH="$ORIGINAL_TEST_PATH"
test "$(readlink "$MIGRATION_HOME/.local/bin/context")" = "$LEGACY_CLI"
for agent in .codex .claude; do
  cmp -s "$TMP_ROOT/before-cli-migration.md" "$MIGRATION_HOME/$agent/skills/context-handoff/SKILL.md"
done
test -z "$(find "$MIGRATION_HOME" -maxdepth 1 -name '.context-agent-tools.*' -print -quit)"
printf 'Agent tools installer checks passed.\n'
