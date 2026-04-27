#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PitcherPlant"
SCHEME="PitcherPlantApp"
CONFIGURATION="Release"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PitcherPlantApp.xcodeproj"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/archive/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$BUILD_DIR/dist"
CHECK_DIR="$BUILD_DIR/checks"
DISTRIBUTION="ad-hoc"
NOTARIZE="false"

usage() {
  cat <<USAGE
usage: $0 [--distribution ad-hoc|developer-id] [--notarize]

Environment for developer-id distribution:
  APPLE_TEAM_ID
  APPLE_SIGNING_IDENTITY
  APPLE_ID
  APPLE_APP_SPECIFIC_PASSWORD
USAGE
}

cleanup_mounts() {
  local dmg_mount_root="$CHECK_DIR/dmg-mount"
  [[ -d "$dmg_mount_root" ]] || return 0

  while IFS= read -r mounted_volume; do
    hdiutil detach "$mounted_volume" >/dev/null 2>&1 || diskutil unmount "$mounted_volume" >/dev/null 2>&1 || true
  done < <(find "$dmg_mount_root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)
}

trap cleanup_mounts EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --distribution)
      DISTRIBUTION="${2:-}"
      shift 2
      ;;
    --notarize)
      NOTARIZE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

case "$DISTRIBUTION" in
  ad-hoc|developer-id)
    ;;
  *)
    echo "Unsupported distribution: $DISTRIBUTION" >&2
    exit 2
    ;;
esac

require_env() {
  local missing=0
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      echo "Missing required environment variable: $name" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

archive_ad_hoc() {
  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-"

  ditto "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/$APP_NAME.app"
}

archive_developer_id() {
  require_env APPLE_TEAM_ID APPLE_SIGNING_IDENTITY

  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$APPLE_SIGNING_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

  cat > "$BUILD_DIR/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>$APPLE_SIGNING_IDENTITY</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$APPLE_TEAM_ID</string>
</dict>
</plist>
PLIST

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/exportOptions.plist"
}

notarize_app_if_requested() {
  [[ "$NOTARIZE" == "true" ]] || return 0
  require_env APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID

  local app_notary_zip="$DIST_DIR/$APP_NAME-app-notary.zip"
  ditto -c -k --keepParent "$EXPORT_DIR/$APP_NAME.app" "$app_notary_zip"
  xcrun notarytool submit "$app_notary_zip" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$EXPORT_DIR/$APP_NAME.app"
  xcrun stapler validate "$EXPORT_DIR/$APP_NAME.app"
  rm -f "$app_notary_zip"
}

package_archive_and_symbols() {
  ditto -c -k --keepParent "$ARCHIVE_PATH" "$DIST_DIR/$APP_NAME.xcarchive.zip"

  if [[ -d "$ARCHIVE_PATH/dSYMs" ]]; then
    ditto -c -k --keepParent "$ARCHIVE_PATH/dSYMs" "$DIST_DIR/$APP_NAME-dSYMs.zip"
  else
    mkdir -p "$BUILD_DIR/empty-dSYMs"
    ditto -c -k --keepParent "$BUILD_DIR/empty-dSYMs" "$DIST_DIR/$APP_NAME-dSYMs.zip"
  fi
}

package_app() {
  local app_bundle="$EXPORT_DIR/$APP_NAME.app"
  local staging_dir="$BUILD_DIR/dmg"

  test -d "$app_bundle"
  mkdir -p "$staging_dir"
  ditto -c -k --keepParent "$app_bundle" "$DIST_DIR/$APP_NAME-macOS.zip"
  rm -rf "$staging_dir"/*
  cp -R "$app_bundle" "$staging_dir/"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$DIST_DIR/$APP_NAME-macOS.dmg"
}

notarize_dmg_if_requested() {
  [[ "$NOTARIZE" == "true" ]] || return 0
  require_env APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID

  xcrun notarytool submit "$DIST_DIR/$APP_NAME-macOS.dmg" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$DIST_DIR/$APP_NAME-macOS.dmg"
  xcrun stapler validate "$DIST_DIR/$APP_NAME-macOS.dmg"
}

verify_artifacts() {
  local app_bundle="$EXPORT_DIR/$APP_NAME.app"
  local zip_path="$DIST_DIR/$APP_NAME-macOS.zip"
  local dmg_path="$DIST_DIR/$APP_NAME-macOS.dmg"
  local zip_check_dir="$CHECK_DIR/zip"
  local dmg_mount_root="$CHECK_DIR/dmg-mount"

  codesign --verify --deep --strict --verbose=2 "$app_bundle"
  hdiutil verify "$dmg_path"

  cleanup_mounts

  rm -rf "$zip_check_dir" "$dmg_mount_root"
  mkdir -p "$zip_check_dir" "$dmg_mount_root"
  ditto -x -k "$zip_path" "$zip_check_dir"
  test -d "$zip_check_dir/$APP_NAME.app"
  codesign --verify --deep --strict --verbose=2 "$zip_check_dir/$APP_NAME.app"

  local mount_point
  hdiutil attach "$dmg_path" -readonly -nobrowse -mountroot "$dmg_mount_root"
  mount_point="$(find "$dmg_mount_root" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  test -n "$mount_point"
  test -d "$mount_point/$APP_NAME.app"
  hdiutil detach "$mount_point"

  if [[ "$NOTARIZE" == "true" ]]; then
    xcrun stapler validate "$app_bundle"
    xcrun stapler validate "$zip_check_dir/$APP_NAME.app"
    spctl --assess --type execute --verbose=4 "$app_bundle"
    spctl --assess --type execute --verbose=4 "$zip_check_dir/$APP_NAME.app"
    spctl --assess --type open --verbose=4 "$dmg_path"
  fi
}

generate_checksums_and_notes() {
  shasum -a 256 \
    "$DIST_DIR/$APP_NAME-macOS.zip" \
    "$DIST_DIR/$APP_NAME-macOS.dmg" \
    "$DIST_DIR/$APP_NAME.xcarchive.zip" \
    "$DIST_DIR/$APP_NAME-dSYMs.zip" \
    > "$DIST_DIR/$APP_NAME-macOS-checksums.txt"

  if [[ "$DISTRIBUTION" == "developer-id" && "$NOTARIZE" == "true" ]]; then
    cat > "$DIST_DIR/release-notes.md" <<NOTES
PitcherPlant macOS release.

- Distribution: Developer ID signed and notarized.
- Artifacts: ZIP, DMG, xcarchive, dSYM archive, SHA-256 checksums.
NOTES
  else
    cat > "$DIST_DIR/release-notes.md" <<NOTES
PitcherPlant macOS ad-hoc release.

- Distribution: ad-hoc signed, not notarized.
- Artifacts: ZIP, DMG, xcarchive, dSYM archive, SHA-256 checksums.
- Gatekeeper may require Control-click > Open, System Settings > Privacy & Security > Open Anyway, or removing quarantine for local testing.
NOTES
  fi
}

rm -rf "$BUILD_DIR/archive" "$EXPORT_DIR" "$DIST_DIR" "$CHECK_DIR" "$BUILD_DIR/dmg" "$BUILD_DIR/empty-dSYMs"
mkdir -p "$BUILD_DIR/archive" "$EXPORT_DIR" "$DIST_DIR" "$CHECK_DIR"

if [[ "$DISTRIBUTION" == "developer-id" ]]; then
  archive_developer_id
else
  archive_ad_hoc
fi

notarize_app_if_requested
package_archive_and_symbols
package_app
notarize_dmg_if_requested
verify_artifacts
generate_checksums_and_notes

printf 'Created release artifacts in %s\n' "$DIST_DIR"
