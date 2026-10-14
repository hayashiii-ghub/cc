#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cc:"
APP_BUNDLE_NAME="cc"
APP_EXECUTABLE_NAME="Context"
LEGACY_BUNDLE_NAME="Context"
BUNDLE_ID="work.hayashigoto.Context"
ZIP_URL="https://github.com/hayashiii-ghub/context/releases/latest/download/context-macos.zip"
TMP_DIR="$(mktemp -d)"
ZIP_PATH="$TMP_DIR/context-macos.zip"
EXTRACT_DIR="$TMP_DIR/extract"
INSTALL_HOME="${CONTEXT_INSTALL_HOME:-$HOME}"
INSTALL_HOME="${INSTALL_HOME%/}"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

validate_app() {
  local app="$1"
  local info_plist="$app/Contents/Info.plist"
  local version

  [[ -d "$app" && ! -L "$app" && -f "$info_plist" ]] || return 1
  [[ "$(plutil -extract CFBundleIdentifier raw "$info_plist" 2>/dev/null)" == "$BUNDLE_ID" ]] || return 1
  [[ "$(plutil -extract CFBundleExecutable raw "$info_plist" 2>/dev/null)" == "$APP_EXECUTABLE_NAME" ]] || return 1
  [[ -x "$app/Contents/MacOS/$APP_EXECUTABLE_NAME" ]] || return 1
  version="$(plutil -extract CFBundleShortVersionString raw "$info_plist" 2>/dev/null)"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  codesign --verify --deep --strict "$app"
}

choose_install_dir() {
  if [[ -n "${CONTEXT_INSTALL_DIR:-}" ]]; then
    printf '%s\n' "$CONTEXT_INSTALL_DIR"
    return
  fi

  local directory
  for directory in /Applications "$HOME/Applications"; do
    if [[ -d "$directory/$APP_BUNDLE_NAME.app" || -d "$directory/$LEGACY_BUNDLE_NAME.app" ]]; then
      printf '%s\n' "$directory"
      return
    fi
  done
  if [[ -w /Applications ]]; then
    printf '%s\n' /Applications
  else
    printf '%s\n' "$HOME/Applications"
  fi
}

# Keep the transaction in a subshell so its EXIT trap also runs after an
# unexpected command failure, with all backup paths still in scope.
install_app() (
  local source_app="$1"
  local destination_app="$2"
  local install_dir="$(dirname "$destination_app")"
  local legacy_app="$install_dir/$LEGACY_BUNDLE_NAME.app"
  local staged_app="$install_dir/.$APP_BUNDLE_NAME.app.new.$$"
  local backup_app="$install_dir/.$APP_BUNDLE_NAME.app.backup.$$"
  local legacy_backup="$install_dir/.$LEGACY_BUNDLE_NAME.app.backup.$$"
  local cli_destination="$INSTALL_HOME/.local/bin/context"
  local cli_binary="$destination_app/Contents/Helpers/context"
  local legacy_cli="$legacy_app/Contents/Helpers/context"
  local cli_staging=""
  local cli_installed=0
  local app_installed=0
  local success=0
  local use_sudo=0

  if [[ ! -w "$install_dir" ]]; then
    use_sudo=1
    echo "Installing to $install_dir requires administrator permission."
  fi

  run_install() {
    if (( use_sudo )); then
      sudo "$@"
    else
      "$@"
    fi
  }

  rollback_install() {
    local rollback_failed=0
    if [[ "$success" != 1 ]]; then
      if [[ "$cli_installed" == 1 ]]; then
        if [[ -L "$cli_destination" && "$(readlink "$cli_destination")" == "$cli_binary" ]]; then
          rm -f "$cli_destination" || rollback_failed=1
        else
          rollback_failed=1
        fi
      fi
      if [[ -n "$cli_staging" && -L "$cli_staging/previous" ]]; then
        if [[ ! -e "$cli_destination" && ! -L "$cli_destination" ]]; then
          mv "$cli_staging/previous" "$cli_destination" || rollback_failed=1
        else
          rollback_failed=1
        fi
      fi
      if [[ "$app_installed" == 1 ]]; then
        run_install rm -rf "$destination_app" || rollback_failed=1
      fi
      if [[ -e "$backup_app" ]]; then
        if [[ ! -e "$destination_app" && ! -L "$destination_app" ]]; then
          run_install mv "$backup_app" "$destination_app" || rollback_failed=1
        else
          rollback_failed=1
        fi
      fi
      if [[ -e "$legacy_backup" ]]; then
        if [[ ! -e "$legacy_app" && ! -L "$legacy_app" ]]; then
          run_install mv "$legacy_backup" "$legacy_app" || rollback_failed=1
        else
          rollback_failed=1
        fi
      fi
    else
      run_install rm -rf "$backup_app" || rollback_failed=1
    fi
    run_install rm -rf "$staged_app" || rollback_failed=1
    if [[ "$rollback_failed" == 1 ]]; then
      printf 'Installation recovery needs attention. Preserved backups: %s, %s, %s\n' \
        "$backup_app" "$legacy_backup" "$cli_staging" >&2
    elif [[ -n "$cli_staging" ]]; then
      rm -rf "$cli_staging"
    fi
  }
  local existing
  for existing in "$destination_app" "$legacy_app"; do
    if [[ -e "$existing" || -L "$existing" ]]; then
      [[ -d "$existing" && ! -L "$existing" \
          && "$(plutil -extract CFBundleIdentifier raw "$existing/Contents/Info.plist" 2>/dev/null)" == "$BUNDLE_ID" ]] \
        || { echo "Preserving an unrelated app or symlink: $existing" >&2; exit 1; }
    fi
  done
  for existing in "$staged_app" "$backup_app" "$legacy_backup"; do
    [[ ! -e "$existing" && ! -L "$existing" ]] \
      || { echo "Preserving an existing recovery path: $existing" >&2; exit 1; }
  done
  trap 'status=$?; rollback_install; exit "$status"' EXIT
  trap 'exit 130' HUP INT TERM

  run_install ditto "$source_app" "$staged_app"
  validate_app "$staged_app" \
    || { echo "Staged $APP_BUNDLE_NAME.app failed validation" >&2; exit 1; }

  # Only the exact link installed for this location is eligible for migration.
  # Leave custom commands, unknown links, and agent skill directories untouched.
  if [[ ! -L "$INSTALL_HOME/.local" && ! -L "$INSTALL_HOME/.local/bin" \
      && -L "$cli_destination" && "$(readlink "$cli_destination")" == "$legacy_cli" ]]; then
    [[ -x "$staged_app/Contents/Helpers/context" ]] \
      || { echo "The archive lacks the CLI required by the existing installation." >&2; exit 1; }
    cli_staging="$(mktemp -d "$INSTALL_HOME/.local/bin/.context-link.XXXXXX")"
    ln -s "$cli_binary" "$cli_staging/new"
  fi

  if [[ -e "$destination_app" ]]; then
    run_install mv "$destination_app" "$backup_app"
  fi
  if [[ -e "$legacy_app" ]]; then
    run_install mv "$legacy_app" "$legacy_backup"
  fi
  run_install mv "$staged_app" "$destination_app"
  app_installed=1
  validate_app "$destination_app" \
    || { echo "Installed $APP_BUNDLE_NAME.app failed validation" >&2; exit 1; }

  if [[ -n "$cli_staging" ]]; then
    [[ -L "$cli_destination" && "$(readlink "$cli_destination")" == "$legacy_cli" ]] \
      || { echo "The CLI changed during installation; preserving it." >&2; exit 1; }
    mv "$cli_destination" "$cli_staging/previous"
    mv "$cli_staging/new" "$cli_destination"
    cli_installed=1
  fi
  run_install xattr -dr com.apple.quarantine "$destination_app" 2>/dev/null || true
  success=1
  if [[ -e "$legacy_backup" ]]; then
    printf 'Preserved previous Context.app at %s\n' "$legacy_backup"
  fi
)

INSTALL_DIR="$(choose_install_dir)"
INSTALL_DIR="${INSTALL_DIR%/}"
[[ "$INSTALL_DIR" == /* && ! -L "$INSTALL_DIR" ]] \
  || { echo "CONTEXT_INSTALL_DIR must be an absolute directory, not a symlink." >&2; exit 1; }
[[ "$INSTALL_HOME" == /* && -d "$INSTALL_HOME" && ! -L "$INSTALL_HOME" ]] \
  || { echo "CONTEXT_INSTALL_HOME must be an existing absolute directory." >&2; exit 1; }
DESTINATION_APP="$INSTALL_DIR/$APP_BUNDLE_NAME.app"

if [[ -n "${CONTEXT_ZIP_PATH:-}" ]]; then
  echo "Using local $APP_NAME archive..."
  cp "$CONTEXT_ZIP_PATH" "$ZIP_PATH"
else
  echo "Downloading latest $APP_NAME..."
  curl -L --fail -A "Mozilla/5.0" -o "$ZIP_PATH" "$ZIP_URL"
fi
mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
SOURCE_APP="$EXTRACT_DIR/$APP_BUNDLE_NAME.app"
if [[ ! -e "$SOURCE_APP" && ! -L "$SOURCE_APP" ]]; then
  SOURCE_APP="$EXTRACT_DIR/$LEGACY_BUNDLE_NAME.app"
fi
validate_app "$SOURCE_APP" \
  || { echo "Archive did not contain a valid cc.app or legacy Context.app" >&2; exit 1; }

if [[ "${CONTEXT_SKIP_STOP:-0}" != 1 ]]; then
  echo "Stopping running $APP_NAME..."
  pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
fi
mkdir -p "$INSTALL_DIR"
echo "Installing to $DESTINATION_APP..."
install_app "$SOURCE_APP" "$DESTINATION_APP"
if [[ "${CONTEXT_SKIP_OPEN:-0}" != 1 ]]; then
  open "$DESTINATION_APP"
fi
echo "Updated $APP_NAME at $DESTINATION_APP"
