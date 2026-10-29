#!/bin/bash
# Builds Zemy.app into ./build — drag it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

# SwiftUI's @State macro plugin ships with Xcode, not the Command Line Tools.
if [ -d /Applications/Xcode.app ]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi

APP=build/Zemy.app
VERSION=1.0

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
  <key>CFBundleVersion</key><string>1</string>
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

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

rm -rf "$ICONSET" build/icon-1024.png
echo "✓ Built $APP ($(du -sh "$APP" | cut -f1))"
