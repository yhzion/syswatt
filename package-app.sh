#!/bin/bash
set -e

cd "$(dirname "$0")"

BINARY=".build/release/syswatt"
APP="SysWatt.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# 버전의 단일 진실은 VERSION 파일 하나다. 태그는 여기서 만들고, Info.plist 도
# 여기에 쓴다. 어긋난 채로 패키징하면 릴리스 자산과 실행 파일 버전이 달라진다.
if [[ ! -f VERSION ]]; then
    echo "VERSION 파일이 없습니다 (시멘틱 버전 한 줄)." >&2
    exit 1
fi
VERSION="$(tr -d '[:space:]' <VERSION)"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION 은 x.y.z 형식이어야 합니다: '$VERSION'" >&2
    exit 1
fi

echo "🔨 Building (release)..."
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BINARY" "$MACOS/"

# $VERSION 을 전개해야 하므로 heredoc 을 인용하지 않는다. plist 에 다른 $ 가 없어 안전하다.
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>SysWatt</string>
    <key>CFBundleExecutable</key>
    <string>syswatt</string>
    <key>CFBundleIdentifier</key>
    <string>com.yhzion.syswatt</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SysWatt</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

codesign --force --deep --sign - "$APP"

echo "✅ Packaged: $APP"
echo ""
echo "🚀 open $APP"
