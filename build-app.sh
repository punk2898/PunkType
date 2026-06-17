#!/bin/bash
# Build PunkType.app bundle
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="PunkType"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/release"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "🔨 Building $APP_NAME..."

# Build release binary
swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release

# Find built binary (skip .dSYM debug symbols)
BINARY="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    BINARY="$BUILD_DIR/release/$APP_NAME"
fi
if [ ! -f "$BINARY" ]; then
    BINARY=$(find "$BUILD_DIR" -name "$APP_NAME" -type f ! -path "*.dSYM*" | grep -v dSYM | head -1)
fi
if [ -z "$BINARY" ]; then
    echo "❌ Could not find built binary"
    exit 1
fi

echo "📦 Creating .app bundle at $APP_BUNDLE"

# Clean and create structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Copy icon
cp "$PROJECT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PunkType</string>
    <key>CFBundleIdentifier</key>
    <string>com.punk2898.punktype</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>PunkType</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>PunkType needs speech recognition to convert your voice to text.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>PunkType needs microphone access to record your voice.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>PunkType uses Apple Events to paste text into other applications.</string>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Code sign: prefer a stable Apple Development identity so TCC permissions
# (Accessibility/Microphone) survive rebuilds; fall back to ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')
if [ -n "$IDENTITY" ]; then
    echo "🔏 Signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" "$APP_BUNDLE"
else
    echo "🔏 Signing ad-hoc (permissions will reset on each reinstall)"
    codesign --force --sign - "$APP_BUNDLE" 2>/dev/null
fi

echo "✅ $APP_NAME.app created at $APP_BUNDLE"
echo "   Double-click to run, or move to /Applications"
