#!/bin/bash
# Archive the app for an App Store submission.
#
#   ./scripts/archive_appstore.sh            # archive only
#   ./scripts/archive_appstore.sh --upload   # archive, then upload with altool
#
# The upload needs App Store Connect API credentials:
#   ASC_KEY_ID    the key id from Users and Access -> Integrations -> App Store Connect API
#   ASC_ISSUER_ID the issuer id of the same key
#
# The signing team is the DEVELOPMENT_TEAM in the Xcode project. It has to be an
# enrolled organisation: a personal team cannot create an App Store Connect
# record or upload a build.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/OpenCodeClient/OpenCodeClient.xcodeproj"
SCHEME="OpenCodeClient"
ARCHIVE_DIR="${ARCHIVE_DIR:-$REPO_ROOT/.occlient/AppStore}"
ARCHIVE_PATH="$ARCHIVE_DIR/OpenCodeClient.xcarchive"
UPLOAD=0
[ "${1:-}" = "--upload" ] && UPLOAD=1

mkdir -p "$ARCHIVE_DIR"

# Every archive carries a fresh build number, so no two uploads claim the
# same one and the version in App Store Connect always has a newer build to
# pick up. Set OPENCODE_SKIP_BUILD_BUMP=1 to keep the current number.
if [ "${OPENCODE_SKIP_BUILD_BUMP:-0}" != "1" ]; then
  "$REPO_ROOT/scripts/bump_build.sh"
else
  echo "==> Keeping build $(./scripts/bump_build.sh --show) (OPENCODE_SKIP_BUILD_BUMP=1)"
fi

echo "==> Archiving $SCHEME (Release)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

echo "==> Archived to $ARCHIVE_PATH"
echo "    bundle id:  com.prysm.opencode"
# The archive's own Info.plist keeps these under ApplicationProperties; the
# app bundle's Info.plist keeps them at the top level.
archive_plist() {
  /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:$1" "$ARCHIVE_PATH/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Print :$1" "$ARCHIVE_PATH/Products/Applications/OpenCodeClient.app/Info.plist" 2>/dev/null \
    || echo unknown
}
echo "    version:    $(archive_plist CFBundleShortVersionString)"
echo "    build:      $(archive_plist CFBundleVersion)"

if [ "$UPLOAD" = "1" ]; then
  if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
    echo "error: ASC_KEY_ID and ASC_ISSUER_ID must be set to upload" >&2
    exit 1
  fi
  echo "==> Uploading"
  xcrun altool --upload-app -f "$ARCHIVE_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
fi
