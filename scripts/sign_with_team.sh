#!/bin/zsh
# Point the project at an organisation team, re-archive, and verify the result
# is signed for App Store distribution.
#
#   ./scripts/sign_with_team.sh <TEAMID>
#
# The team id is the legacy 10-character id that appears in the certificate
# name in the keychain: "Apple Distribution: <name> (<TEAMID>)".
set -euo pipefail

TEAM="${1:-}"
[ -n "$TEAM" ] || { echo "usage: $0 <TEAMID>" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/OpenCodeClient/OpenCodeClient.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
ARCHIVE_DIR="${ARCHIVE_DIR:-$REPO_ROOT/.occlient/AppStore}"
ARCHIVE_PATH="$ARCHIVE_DIR/OpenCodeClient.xcarchive"

echo "==> Setting DEVELOPMENT_TEAM = $TEAM"
/usr/bin/sed -i '' "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = $TEAM;/g" "$PBXPROJ"
echo "    $(grep -c "DEVELOPMENT_TEAM = $TEAM;" "$PBXPROJ") configurations updated"
echo "    remaining old ids: $(grep -oE 'DEVELOPMENT_TEAM = [A-Z0-9]*;' "$PBXPROJ" | sort -u | tr '\n' ' ')"

echo "==> Archiving"
rm -rf "$ARCHIVE_PATH"
mkdir -p "$ARCHIVE_DIR"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme OpenCodeClient \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

echo "==> Signed as"
/usr/bin/codesign -dv --verbose=2 "$ARCHIVE_PATH/Products/Applications/OpenCodeClient.app" 2>&1 \
  | grep -E 'Authority|TeamIdentifier' | head -4

echo "==> Embedded profile"
/usr/bin/security cms -D -i "$ARCHIVE_PATH/Products/Applications/OpenCodeClient.app/embedded.mobileprovision" 2>/dev/null \
  | /usr/bin/python3 -c "
import sys, plistlib
d = plistlib.loads(sys.stdin.buffer.read())
e = d['Entitlements']
print('   name              :', d.get('Name'))
print('   team              :', d.get('TeamIdentifier'))
print('   app id            :', e.get('application-identifier'))
print('   get-task-allow    :', e.get('get-task-allow'))
print('   beta-reports-active:', e.get('beta-reports-active'))
"

echo "==> Upload"
if [ "${1:-}" != "--upload" ] && [ -z "${ASC_KEY_ID:-}" ]; then
  echo "    skipped: set ASC_KEY_ID and ASC_ISSUER_ID, then re-run with --upload"
  exit 0
fi
xcrun altool --upload-app -f "$ARCHIVE_PATH" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
