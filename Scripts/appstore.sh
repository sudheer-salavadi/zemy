#!/bin/bash
# Archives the sandboxed Mac App Store build and exports it (default) or uploads it (--upload).
# Signing and upload use the account signed in to Xcode. TEAM_ID overrides the detected company team.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

OUT=build/appstore
ICONSET=$OUT/Assets.xcassets/AppIcon.appiconset
TEAM_ID="${TEAM_ID:-$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
  | awk '/teamID =/{id=$3} /teamType = Company/{gsub(";","",id); print id; exit}')}"
[ -n "$TEAM_ID" ] || { echo "No company team found in Xcode; set TEAM_ID"; exit 1; }
DEST=export; [ "${1:-}" = "--upload" ] && DEST=upload

echo "▸ Icon…"
rm -rf "$OUT" && mkdir -p "$ICONSET"
swift Scripts/make-icon.swift "$OUT/icon-1024.png"
images=""
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/icon-1024.png" --out "$ICONSET/icon_${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$OUT/icon-1024.png" --out "$ICONSET/icon_${s}@2x.png" >/dev/null
  images+="{\"idiom\":\"mac\",\"size\":\"${s}x${s}\",\"scale\":\"1x\",\"filename\":\"icon_${s}.png\"},"
  images+="{\"idiom\":\"mac\",\"size\":\"${s}x${s}\",\"scale\":\"2x\",\"filename\":\"icon_${s}@2x.png\"},"
done
echo "{\"images\":[${images%,}],\"info\":{\"version\":1,\"author\":\"xcode\"}}" > "$ICONSET/Contents.json"
echo '{"info":{"version":1,"author":"xcode"}}' > "$OUT/Assets.xcassets/Contents.json"

echo "▸ Project…"
xcodegen generate --spec AppStore/project.yml --quiet

echo "▸ Archive…"
xcodebuild archive -project AppStore/ZemyAppStore.xcodeproj -scheme Zemy -configuration Release \
  -archivePath "$OUT/Zemy.xcarchive" -destination 'generic/platform=macOS' \
  DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates -quiet

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>${DEST}</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "▸ Export ($DEST)…"
xcodebuild -exportArchive -archivePath "$OUT/Zemy.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet
echo "✓ ${DEST} done ($OUT/export)"
