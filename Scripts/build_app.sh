#!/bin/bash
set -euo pipefail

# Builds release binaries and packages MailSorter.app for ~/Applications.

cd "$(dirname "$0")/.."

CONFIG="release"
APP_NAME="MailSorter"
BUNDLE_ID="com.junwoo.mailsorter"
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "▶︎ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)

echo "▶︎ Creating .app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/MailSorterApp" "$MACOS_DIR/$APP_NAME"
cp "$BIN_DIR/MailSorterDaemon" "$MACOS_DIR/MailSorterDaemon"

if [ -d "$BIN_DIR/MailSorterApp_MailSorterApp.bundle" ]; then
    cp -R "$BIN_DIR/MailSorterApp_MailSorterApp.bundle" "$RESOURCES_DIR/"
fi

# Copy icon if exists
if [ -f "icon_temp/icon.iconset/icon_512x512.png" ]; then
    iconutil -c icns "icon_temp/icon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>8</string>
    <key>CFBundleShortVersionString</key><string>0.4.1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© junwoo</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
echo "✓ Built $APP_DIR"
echo
echo "다음 단계:"
echo "  1. open '$APP_DIR'  ← 메뉴바 트레이 아이콘 확인"
echo "  2. 환경설정에서 IMAP 계정 입력"
echo "  3. 데몬 탭에서 '로그인 시 자동 시작' 토글 ON"
