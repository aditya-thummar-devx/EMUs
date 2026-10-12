#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="EMUs"
APP_BUNDLE="${DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${DIR}/${DMG_NAME}"
DMG_STAGING="${DIR}/dmg_staging"

echo "=== 1. Building release binary ==="
swift build -c release --package-path "${DIR}"

echo "=== 2. Creating .app bundle structure ==="
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "${DIR}/.build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Create Info.plist with LSUIElement=1 so no Dock icon is shown
cat << 'EOF' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>EMUs</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.EMUs</string>
    <key>CFBundleName</key>
    <string>EMUs</string>
    <key>CFBundleDisplayName</key>
    <string>EMUs</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "=== 3. Ad-hoc signing the .app bundle ==="
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "=== 4. Packaging into .dmg ==="
rm -rf "${DMG_STAGING}" "${DMG_PATH}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"

# Add shortcut to Applications folder
ln -s /Applications "${DMG_STAGING}/Applications"

# Create the DMG image
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING}" -ov -format UDZO "${DMG_PATH}"

rm -rf "${DMG_STAGING}"

echo "=== Build and packaging complete! ==="
echo "App bundle: ${APP_BUNDLE}"
echo "DMG output: ${DMG_PATH}"
