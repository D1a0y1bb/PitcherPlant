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
RELEASE_TAG="${RELEASE_TAG:-}"
RELEASE_BUILD_NUMBER="${RELEASE_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
RELEASE_DOWNLOAD_BASE_URL="${RELEASE_DOWNLOAD_BASE_URL:-}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-D1a0y1bb.PitcherPlant}"
SPARKLE_ED_PRIVATE_KEY="${SPARKLE_ED_PRIVATE_KEY:-}"
SPARKLE_SIGN_UPDATE_PATH="${SPARKLE_SIGN_UPDATE_PATH:-}"

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

resolve_sparkle_sign_update() {
  local candidate

  if [[ -n "$SPARKLE_SIGN_UPDATE_PATH" ]]; then
    if [[ -x "$SPARKLE_SIGN_UPDATE_PATH" ]]; then
      printf '%s\n' "$SPARKLE_SIGN_UPDATE_PATH"
      return 0
    fi
    echo "Configured SPARKLE_SIGN_UPDATE_PATH is not executable: $SPARKLE_SIGN_UPDATE_PATH" >&2
    exit 1
  fi

  for candidate in \
    "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
    "$ROOT_DIR/.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
    "$ROOT_DIR/.build/index-build/artifacts/sparkle/Sparkle/bin/sign_update"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$ROOT_DIR/.build" -path '*/Sparkle/bin/sign_update' -type f -print 2>/dev/null)

  echo "Unable to find Sparkle sign_update. Build or resolve packages before packaging releases." >&2
  exit 1
}

sparkle_signature_attributes() {
  local update_archive="$1"
  local sign_update_path
  sign_update_path="$(resolve_sparkle_sign_update)"

  if [[ -n "$SPARKLE_ED_PRIVATE_KEY" ]]; then
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update_path" --ed-key-file - "$update_archive"
  else
    "$sign_update_path" --account "$SPARKLE_ACCOUNT" "$update_archive"
  fi
}

XCODEBUILD_RELEASE_SETTINGS=()
if [[ -n "$RELEASE_BUILD_NUMBER" ]]; then
  XCODEBUILD_RELEASE_SETTINGS+=(CURRENT_PROJECT_VERSION="$RELEASE_BUILD_NUMBER")
fi
if [[ "$RELEASE_TAG" == v* ]]; then
  XCODEBUILD_RELEASE_SETTINGS+=(MARKETING_VERSION="${RELEASE_TAG#v}")
fi

archive_ad_hoc() {
  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    PP_RELEASE_TAG="$RELEASE_TAG" \
    "${XCODEBUILD_RELEASE_SETTINGS[@]}" \
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
    PP_RELEASE_TAG="$RELEASE_TAG" \
    "${XCODEBUILD_RELEASE_SETTINGS[@]}" \
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
  ln -s /Applications "$staging_dir/Applications"
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
  test -L "$mount_point/Applications"
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
  local app_bundle="$EXPORT_DIR/$APP_NAME.app"
  local short_version
  local bundle_version
  local release_title
  local commit_sha
  local short_commit
  local commit_line
  local previous_tag
  local changes_heading
  local change_log
  local distribution_line
  local trust_note

  (
    cd "$DIST_DIR"
    shasum -a 256 \
      "$APP_NAME-macOS.zip" \
      "$APP_NAME-macOS.dmg" \
      "$APP_NAME.xcarchive.zip" \
      "$APP_NAME-dSYMs.zip" \
      > "$APP_NAME-macOS-checksums.txt"
  )

  short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_bundle/Contents/Info.plist")"
  bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_bundle/Contents/Info.plist")"
  release_title="${RELEASE_TAG:-$APP_NAME $short_version}"
  commit_sha="${GITHUB_SHA:-}"
  if [[ -z "$commit_sha" ]] && git rev-parse --show-toplevel >/dev/null 2>&1; then
    commit_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  fi
  short_commit="${commit_sha:0:12}"
  if [[ -n "$short_commit" && -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    commit_line="- Commit: [\`$short_commit\`](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${commit_sha})"
  elif [[ -n "$short_commit" ]]; then
    commit_line="- Commit: \`$short_commit\`"
  else
    commit_line="- Commit: unavailable in this build environment"
  fi

  previous_tag=""
  changes_heading="Changes in this release"
  change_log=""
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    if [[ -n "$RELEASE_TAG" ]] && git rev-parse "$RELEASE_TAG^" >/dev/null 2>&1; then
      previous_tag="$(git describe --tags --abbrev=0 "$RELEASE_TAG^" 2>/dev/null || true)"
    elif git rev-parse HEAD^ >/dev/null 2>&1; then
      previous_tag="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
    fi

    if [[ -n "$previous_tag" ]]; then
      changes_heading="Changes since $previous_tag"
      change_log="$(git log --no-merges --pretty='- `%h` %s' "$previous_tag"..HEAD 2>/dev/null | head -n 20 || true)"
    else
      change_log="$(git log --no-merges --pretty='- `%h` %s' -n 10 2>/dev/null || true)"
    fi
  fi
  if [[ -z "$change_log" ]]; then
    change_log="- Built from the current source checkout."
  fi

  if [[ "$DISTRIBUTION" == "developer-id" && "$NOTARIZE" == "true" ]]; then
    distribution_line="Developer ID signed and notarized."
    trust_note="Gatekeeper should accept the app normally after download."
  else
    distribution_line="Ad-hoc signed, not notarized."
    trust_note="Gatekeeper may require Control-click > Open, System Settings > Privacy & Security > Open Anyway, or removing quarantine for local testing."
  fi

  cat > "$DIST_DIR/release-notes.md" <<NOTES
PitcherPlant $release_title

### Build

- Version: \`$short_version\`
- Build: \`$bundle_version\`
- Release tag: \`${RELEASE_TAG:-local}\`
$commit_line

### $changes_heading

$change_log

### Distribution

- $distribution_line
- DMG includes \`PitcherPlant.app\` and an \`Applications\` drag-and-drop shortcut.
- Artifacts: ZIP, DMG, Sparkle appcast, xcarchive, dSYM archive, SHA-256 checksums.
- $trust_note
NOTES
}

generate_appcast() {
  local app_bundle="$EXPORT_DIR/$APP_NAME.app"
  local zip_path="$DIST_DIR/$APP_NAME-macOS.zip"
  local appcast_path="$DIST_DIR/appcast.xml"
  local release_base_url="$RELEASE_DOWNLOAD_BASE_URL"
  local sparkle_attributes
  local sparkle_ed_signature
  local sparkle_archive_length

  if [[ -z "$release_base_url" && -n "${GITHUB_REPOSITORY:-}" && -n "$RELEASE_TAG" ]]; then
    release_base_url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${RELEASE_TAG}"
  fi
  if [[ -z "$release_base_url" ]]; then
    release_base_url="https://github.com/D1a0y1bb/PitcherPlant/releases/download/${RELEASE_TAG:-local}"
  fi

  sparkle_attributes="$(sparkle_signature_attributes "$zip_path")"
  sparkle_ed_signature="$(printf '%s\n' "$sparkle_attributes" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
  sparkle_archive_length="$(printf '%s\n' "$sparkle_attributes" | sed -nE 's/.*length="([0-9]+)".*/\1/p')"
  if [[ -z "$sparkle_ed_signature" || -z "$sparkle_archive_length" ]]; then
    echo "Sparkle sign_update did not return edSignature and length attributes." >&2
    echo "$sparkle_attributes" >&2
    exit 1
  fi

  python3 - "$app_bundle" "$zip_path" "$appcast_path" "$release_base_url" "$RELEASE_TAG" "$sparkle_ed_signature" "$sparkle_archive_length" <<'PY'
import datetime
import email.utils
import html
import plistlib
import sys
from pathlib import Path

app_bundle = Path(sys.argv[1])
zip_path = Path(sys.argv[2])
appcast_path = Path(sys.argv[3])
release_base_url = sys.argv[4].rstrip("/")
release_tag = sys.argv[5]
sparkle_ed_signature = sys.argv[6]
sparkle_archive_length = sys.argv[7]

with (app_bundle / "Contents" / "Info.plist").open("rb") as fh:
    info = plistlib.load(fh)

short_version = str(info.get("CFBundleShortVersionString", "0.0.0"))
bundle_version = str(info.get("CFBundleVersion", short_version))
minimum_system_version = str(info.get("LSMinimumSystemVersion", ""))
title = release_tag or f"PitcherPlant {short_version}"
archive_name = zip_path.name
archive_url = f"{release_base_url}/{archive_name}"
archive_length = int(sparkle_archive_length or zip_path.stat().st_size)
pub_date = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))

minimum_system_version_xml = ""
if minimum_system_version:
    minimum_system_version_xml = f"\n            <sparkle:minimumSystemVersion>{html.escape(minimum_system_version)}</sparkle:minimumSystemVersion>"

sparkle_signature_xml = f'\n                sparkle:edSignature="{html.escape(sparkle_ed_signature, quote=True)}"'

appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>PitcherPlant Updates</title>
        <link>https://github.com/D1a0y1bb/PitcherPlant/releases</link>
        <description>PitcherPlant macOS app updates</description>
        <language>zh-Hans</language>
        <item>
            <title>{html.escape(title)}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{html.escape(bundle_version)}</sparkle:version>
            <sparkle:shortVersionString>{html.escape(short_version)}</sparkle:shortVersionString>{minimum_system_version_xml}
            <enclosure
                url="{html.escape(archive_url, quote=True)}"
                {sparkle_signature_xml.strip()}
                length="{archive_length}"
                type="application/octet-stream" />
        </item>
    </channel>
</rss>
"""
appcast_path.write_text(appcast, encoding="utf-8")
PY
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
generate_appcast

printf 'Created release artifacts in %s\n' "$DIST_DIR"
