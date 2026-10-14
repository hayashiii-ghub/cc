#!/usr/bin/env bash
set -euo pipefail

INSTALL_HOME="${CC_INSTALL_HOME:-$HOME}"
INSTALL_APP="${CC_INSTALL_APP:-}"
if [[ -z "$INSTALL_APP" ]]; then
  for candidate in /Applications/cc.app "$INSTALL_HOME/Applications/cc.app"; do
    if [[ -d "$candidate" ]]; then
      INSTALL_APP="$candidate"
      break
    fi
  done
  INSTALL_APP="${INSTALL_APP:-/Applications/cc.app}"
fi
INSTALL_HOME="${INSTALL_HOME%/}"
INSTALL_APP="${INSTALL_APP%/}"
CLI_BINARY="$INSTALL_APP/Contents/Helpers/cc:"
SKILL_SOURCE="$INSTALL_APP/Contents/Resources/skills/cc-handoff/SKILL.md"
CLI_DESTINATION="$INSTALL_HOME/.local/bin/cc:"
CODEX_DESTINATION="$INSTALL_HOME/.codex/skills/cc-handoff"
CLAUDE_DESTINATION="$INSTALL_HOME/.claude/skills/cc-handoff"
MANIFEST_NAME=".cc-install-manifest"
OWNER_MARKER="cc: cc-handoff installer v1"
PRINT_PLAN=0

if [[ "$#" == 1 && "$1" == --print-plan ]]; then
  PRINT_PLAN=1
elif [[ "$#" != 0 ]]; then
  echo "usage: install_agent_tools.sh [--print-plan]" >&2
  exit 2
fi

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

file_hash() {
  /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

[[ "$INSTALL_HOME" == /* && -d "$INSTALL_HOME" && ! -L "$INSTALL_HOME" ]] \
  || fail "CC_INSTALL_HOME must be an existing absolute directory."
[[ "$INSTALL_APP" == /* && -d "$INSTALL_APP" && ! -L "$INSTALL_APP" ]] \
  || fail "cc: app not found at $INSTALL_APP."
[[ "$(plutil -extract CFBundleIdentifier raw "$INSTALL_APP/Contents/Info.plist")" == work.hayashigoto.cc ]] \
  || fail "The selected app is not cc:."
[[ -x "$CLI_BINARY" && ! -L "$CLI_BINARY" ]] \
  || fail "The selected cc: app does not contain its CLI."
[[ -f "$SKILL_SOURCE" && ! -L "$SKILL_SOURCE" ]] \
  || fail "The selected cc: app does not contain its handoff skill."
SOURCE_HASH="$(file_hash "$SKILL_SOURCE")"

PARENTS=(
  "$INSTALL_HOME/.local" "$INSTALL_HOME/.local/bin"
  "$INSTALL_HOME/.codex" "$INSTALL_HOME/.codex/skills"
  "$INSTALL_HOME/.claude" "$INSTALL_HOME/.claude/skills"
)
for parent in "${PARENTS[@]}"; do
  [[ ! -L "$parent" ]] || fail "Preserving existing symlink: $parent"
  [[ ! -e "$parent" || -d "$parent" ]] || fail "Preserving existing file: $parent"
done

preflight_cli() {
  if [[ -L "$CLI_DESTINATION" ]]; then
    [[ "$(readlink "$CLI_DESTINATION")" == "$CLI_BINARY" ]] \
      || fail "Preserving an unrelated CLI symlink; review before installing: $CLI_DESTINATION"
  elif [[ -e "$CLI_DESTINATION" ]]; then
    fail "Preserving an existing CLI file; review before installing: $CLI_DESTINATION"
  fi
}

preflight_skill() {
  local destination="$1"
  local manifest="$destination/$MANIFEST_NAME"
  local saved_hash
  local extra_files

  [[ ! -L "$destination" ]] || fail "Preserving existing skill symlink: $destination"
  [[ -e "$destination" ]] || return 0
  [[ -d "$destination" && -f "$manifest" && ! -L "$manifest" ]] \
    || fail "Preserving an existing skill without an install manifest: $destination"
  [[ -f "$destination/SKILL.md" && ! -L "$destination/SKILL.md" ]] \
    || fail "Preserving an edited skill: $destination"
  [[ "$(sed -n '1p' "$manifest")" == "$OWNER_MARKER" && "$(wc -l <"$manifest" | tr -d ' ')" == 2 ]] \
    || fail "Preserving an unrecognized skill manifest: $destination"
  saved_hash="$(sed -n '2p' "$manifest")"
  [[ "$saved_hash" =~ ^[0-9a-f]{64}$ && "$(file_hash "$destination/SKILL.md")" == "$saved_hash" ]] \
    || fail "Preserving a user-edited skill: $destination"
  extra_files="$(find "$destination" -mindepth 1 -maxdepth 1 ! -name SKILL.md ! -name "$MANIFEST_NAME" -print -quit)" \
    || fail "Could not inspect the existing skill: $destination"
  [[ -z "$extra_files" ]] \
    || fail "Preserving extra files in the skill: $destination"
}

preflight_cli
preflight_skill "$CODEX_DESTINATION"
preflight_skill "$CLAUDE_DESTINATION"

if [[ "$PRINT_PLAN" == 1 ]]; then
  printf 'CLI link: %s -> %s\nCodex skill: %s\nClaude skill: %s\n' \
    "$CLI_DESTINATION" "$CLI_BINARY" "$CODEX_DESTINATION" "$CLAUDE_DESTINATION"
  exit 0
fi

STAGING_DIR="$(mktemp -d "$INSTALL_HOME/.cc-agent-tools.XXXXXX")"
SUCCESS=0
CLI_INSTALLED=0
CODEX_INSTALLED=0
CLAUDE_INSTALLED=0
CREATED_DIR_COUNT=0
CREATED_DIRS=()

restore_skill() {
  local destination="$1"
  local backup="$2"
  local installed="$3"
  if [[ "$installed" == 1 ]]; then
    rm -rf "$destination" || return 1
  fi
  if [[ -d "$backup" ]]; then
    [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
    mv "$backup" "$destination" || return 1
  fi
}

cleanup() {
  local rollback_failed=0
  local index
  if [[ "$SUCCESS" != 1 ]]; then
    if [[ "$CLI_INSTALLED" == 1 ]]; then
      if [[ -L "$CLI_DESTINATION" && "$(readlink "$CLI_DESTINATION")" == "$CLI_BINARY" ]]; then
        rm -f "$CLI_DESTINATION" || rollback_failed=1
      elif [[ -e "$CLI_DESTINATION" || -L "$CLI_DESTINATION" ]]; then
        rollback_failed=1
      fi
    fi
    restore_skill "$CLAUDE_DESTINATION" "$STAGING_DIR/claude.previous" "$CLAUDE_INSTALLED" || rollback_failed=1
    restore_skill "$CODEX_DESTINATION" "$STAGING_DIR/codex.previous" "$CODEX_INSTALLED" || rollback_failed=1
    for ((index = CREATED_DIR_COUNT - 1; index >= 0; index--)); do
      rmdir "${CREATED_DIRS[index]}" 2>/dev/null || true
    done
  fi
  if [[ "$rollback_failed" == 1 ]]; then
    printf 'Installation rollback needs attention. Preserved recovery files at %s\n' "$STAGING_DIR" >&2
  else
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT

for parent in "${PARENTS[@]}"; do
  if [[ ! -d "$parent" ]]; then
    mkdir "$parent"
    CREATED_DIRS[CREATED_DIR_COUNT]="$parent"
    CREATED_DIR_COUNT=$((CREATED_DIR_COUNT + 1))
  fi
done

stage_skill() {
  local staged="$1"
  mkdir "$staged"
  cp "$SKILL_SOURCE" "$staged/SKILL.md"
  printf '%s\n%s\n' "$OWNER_MARKER" "$SOURCE_HASH" >"$staged/$MANIFEST_NAME"
  chmod 755 "$staged"
  chmod 644 "$staged/SKILL.md" "$staged/$MANIFEST_NAME"
}

commit_skill() {
  local destination="$1"
  local staged="$2"
  local backup="$3"
  local installed_flag="$4"

  preflight_skill "$destination"
  if [[ -d "$destination" ]]; then
    if [[ "$(file_hash "$destination/SKILL.md")" == "$SOURCE_HASH" ]]; then
      return 0
    fi
    mv "$destination" "$backup"
  fi
  printf -v "$installed_flag" '%s' 1
  mv "$staged" "$destination"
}

stage_skill "$STAGING_DIR/codex.new"
stage_skill "$STAGING_DIR/claude.new"
commit_skill "$CODEX_DESTINATION" "$STAGING_DIR/codex.new" "$STAGING_DIR/codex.previous" CODEX_INSTALLED
commit_skill "$CLAUDE_DESTINATION" "$STAGING_DIR/claude.new" "$STAGING_DIR/claude.previous" CLAUDE_INSTALLED
preflight_cli
if [[ ! -L "$CLI_DESTINATION" ]]; then
  ln -s "$CLI_BINARY" "$STAGING_DIR/cli.new"
  CLI_INSTALLED=1
  mv "$STAGING_DIR/cli.new" "$CLI_DESTINATION"
fi
SUCCESS=1
printf 'Installed CLI link: %s\nInstalled Codex skill: %s\nInstalled Claude skill: %s\n' \
  "$CLI_DESTINATION" "$CODEX_DESTINATION" "$CLAUDE_DESTINATION"
