#!/usr/bin/env bash

CONTEXT_APP_NAME="cc:"
CONTEXT_APP_BUNDLE_NAME="cc"
CONTEXT_EXECUTABLE_NAME="Context"
CONTEXT_BUNDLE_ID="work.hayashigoto.Context"
CONTEXT_MIN_SYSTEM_VERSION="26.0"
CONTEXT_SPARKLE_FEED_URL="https://github.com/hayashiii-ghub/context/releases/latest/download/appcast.xml"
CONTEXT_SPARKLE_PUBLIC_ED_KEY="RfBevuBjjY33b182nr6OCFHD3Ifgd+25deHDmpeR9ug="
CONTEXT_RELEASES_URL="https://github.com/hayashiii-ghub/context/releases"
CONTEXT_CLI_NAME="context"
CONTEXT_CLI_PRODUCT_NAME="ContextCLI"

context_copy_bundle_resources() {
  local root_dir="$1"
  local resources_dir="$2"

  xcrun actool "$root_dir/Assets/Context.icon" \
    --compile "$resources_dir" \
    --platform macosx \
    --minimum-deployment-target "$CONTEXT_MIN_SYSTEM_VERSION" \
    --app-icon Context \
    --output-partial-info-plist "$resources_dir/ContextIcon.plist"
  cp "$root_dir/Assets/MenuBarTemplate.svg" "$resources_dir/MenuBarTemplate.svg"
  cp "$root_dir/script/install_agent_tools.sh" "$resources_dir/install_agent_tools.sh"
  chmod +x "$resources_dir/install_agent_tools.sh"
  mkdir -p "$resources_dir/skills"
  ditto "$root_dir/skills/context-handoff" "$resources_dir/skills/context-handoff"
}

context_embed_cli() {
  local app_bundle="$1"
  local cli_binary="$2"
  local destination="$app_bundle/Contents/Helpers/$CONTEXT_CLI_NAME"

  if [[ ! -x "$cli_binary" ]]; then
    echo "cc: CLI executable not found at $cli_binary" >&2
    return 1
  fi
  mkdir -p "$app_bundle/Contents/Helpers"
  cp "$cli_binary" "$destination"
  chmod +x "$destination"
}

context_sign_cli_and_app() {
  local app_bundle="$1"
  local identity="${CONTEXT_CODESIGN_IDENTITY:--}"
  local -a codesign_args=(--force --sign "$identity")

  if [[ "$identity" != "-" ]]; then
    codesign_args+=(--options runtime --timestamp)
  fi
  codesign "${codesign_args[@]}" "$app_bundle/Contents/Helpers/$CONTEXT_CLI_NAME"
  codesign "${codesign_args[@]}" "$app_bundle"
  codesign --verify --deep --strict "$app_bundle"
}

context_write_info_plist() {
  local info_plist="$1"
  local app_version="$2"

  cat >"$info_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$CONTEXT_EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$CONTEXT_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$CONTEXT_APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$CONTEXT_APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>Context.icns</string>
  <key>CFBundleIconName</key>
  <string>Context</string>
  <key>CFBundleShortVersionString</key>
  <string>$app_version</string>
  <key>CFBundleVersion</key>
  <string>$app_version</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$CONTEXT_MIN_SYSTEM_VERSION</string>
  <key>SUFeedURL</key>
  <string>$CONTEXT_SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$CONTEXT_SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>cc: uses Finder access to add your selected files to the shelf.</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$CONTEXT_BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key>
      <array><string>context</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
}
