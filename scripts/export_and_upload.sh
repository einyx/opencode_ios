#!/bin/bash
# Export the latest archive as an App Store .ipa and upload it with the
# App Store Connect API key (MU26W8YJGR).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_DIR="$REPO_ROOT/.occlient/AppStore"
ARCHIVE="$ARCHIVE_DIR/OpenCodeClient.xcarchive"
EXPORT_DIR="$ARCHIVE_DIR/export"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_MU26W8YJGR.p8"
KEY_ID="MU26W8YJGR"
ISSUER_ID="7bfcb655-045e-47c4-88e2-43e0c3988c44"

LATEST=$(ls -td "$ARCHIVE_DIR"/*.xcarchive 2>/dev/null | head -1)
if [ -z "$LATEST" ]; then
  echo "no archive found in $ARCHIVE_DIR" >&2
  exit 1
fi

mkdir -p "$EXPORT_DIR"
cat > "$EXPORT_DIR/exportOptions.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>          <string>app-store-connect</string>
  <key>teamID</key>          <string>9DBH2A7KB8</string>
  <key>uploadSymbols</key>   <true/>
  <key>signingStyle</key>    <string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.prysm.opencode</key>             <string>OpenCode Remote App Store opencode</string>
    <key>com.prysm.opencode.watchkitapp</key> <string>OpenCode Remote App Store watchkitapp</string>
  </dict>
</dict>
</plist>
EOF

echo "==> Exporting $LATEST"
xcodebuild -exportArchive \
  -archivePath "$LATEST" \
  -exportOptionsPlist "$EXPORT_DIR/exportOptions.plist" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID"

IPA=$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1)
if [ -z "$IPA" ]; then
  echo "no .ipa produced" >&2
  exit 1
fi

echo "==> Uploading $IPA"
xcrun altool --upload-app -f "$IPA" \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

echo "==> Uploaded. The build appears in App Store Connect → TestFlight once processed."
