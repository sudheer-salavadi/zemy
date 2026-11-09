#!/bin/bash
# Builds Zemy.app into ./build — drag it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI's @State macro plugin ships with Xcode, not the Command Line Tools.
if [ -d /Applications/Xcode.app ]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi

APP=build/Zemy.app
VERSION=1.1

echo "▸ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Zemy"

echo "▸ Drawing icon…"
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift Scripts/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Zemy"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Vendor/CWebP/COPYING "$APP/Contents/Resources/libwebp-LICENSE.txt"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Zemy</string>
  <key>CFBundleDisplayName</key><string>Zemy</string>
  <key>CFBundleIdentifier</key><string>app.zemy.mac</string>
  <key>CFBundleExecutable</key><string>Zemy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Zemy — the designer's swiss knife</string>
  <key>NSDesktopFolderUsageDescription</key><string>Zemy renames, optimizes and saves the files you choose.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Zemy renames, optimizes and saves the files you choose.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Zemy renames, optimizes and saves the files you choose.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Image</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.image</string><string>public.svg-image</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

rm -rf "$ICONSET" build/icon-1024.png

# Developer ID + notarization when available (SIGN_ID / NOTARY_PROFILE override); ad-hoc otherwise.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-zemy-notary}"
ZIP="build/Zemy-${VERSION}.zip"

if [ -z "$SIGN_ID" ]; then
  echo "▸ Signing (ad-hoc — no Developer ID certificate; downloads will be blocked by Gatekeeper)…"
  codesign --force --deep --sign - "$APP"
  echo "✓ Built $APP ($(du -sh "$APP" | cut -f1))"
  exit 0
fi

echo "▸ Signing ($SIGN_ID)…"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "▸ Notarizing…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
  shasum -a 256 "$ZIP" | sed 's|build/||' > "$ZIP.sha256"
else
  echo "! Signed but not notarized: run xcrun notarytool store-credentials $NOTARY_PROFILE"
fi
echo "✓ Built $APP and $ZIP"
