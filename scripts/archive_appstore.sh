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
echo "    version:    $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ARCHIVE_PATH/Info.plist" 2>/dev/null || echo unknown)"
echo "    build:      $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ARCHIVE_PATH/Info.plist" 2>/dev/null || echo unknown)"

if [ "$UPLOAD" = "1" ]; then
  if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
    echo "error: ASC_KEY_ID and ASC_ISSUER_ID must be set to upload" >&2
    exit 1
  fi
  echo "==> Uploading"
  xcrun altool --upload-app -f "$ARCHIVE_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
fi
