#!/bin/bash
# SysWatt.app 을 배포용 DMG 로 감싼다. 릴리스 워크플로가 이 파일 하나를 부른다.
#
# 만들어놓고 열지 않는 검사는 검사가 아니므로, 마지막에 직접 마운트해서
# .app 이 보이는지 + 서명이 유효한지까지 본다.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

VERSION="$(tr -d '[:space:]' <VERSION)"
NAME="SysWatt-${VERSION}"
STAGE="dist/staging"
MNT="dist/mnt"
DMG="dist/${NAME}.dmg"

rm -rf "$STAGE" "$MNT" "$DMG" "$DMG.sha256"
mkdir -p "$STAGE" "$MNT" dist

./package-app.sh
cp -R SysWatt.app "$STAGE/"
# 드래그해서 넣는 설치 화면 하나. 이 심볼릭이 있어야 DMG 안에서 Applications 가 보인다.
ln -s /Applications "$STAGE/Applications"

echo "📦 Creating DMG..."
hdiutil create -quiet -volname "SysWatt ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "🔍 Mounting and verifying..."
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG"
cleanup() { hdiutil detach -quiet "$MNT" 2>/dev/null || true; }
# 실패로 스크립트가 중간에 죽어도 마운트는 남긴다. trap 이 없으면 DMG 가 걸려서
# 다음 빌드가 귀찮아진다.
trap cleanup EXIT

test -d "$MNT/SysWatt.app" || {
    echo "DMG 안에 SysWatt.app 이 없다" >&2
    exit 1
}
codesign --verify --deep --strict "$MNT/SysWatt.app" && echo "✅ codesign verify"

# DMG 안에서 실제로 도는지 본다. 여기서 -dump 로 센서를 읽는다.
# CI 의 Mac 은 VM 이라 Energy Model / SMC 가 없을 수 있으므로 숫자까지는 요구하지 않는다.
if "$MNT/SysWatt.app/Contents/MacOS/syswatt" --dump >/dev/null 2>&1; then
    echo "✅ DMG 안의 바이너리 실행"
else
    echo "ℹ️ DMG 안의 바이너리가 0 이 아닌 코드로 끝났다 (센서 없는 VM 에서 그럴 수 있다)"
fi

# ad-hoc 서명 + 미공증 상태의 Gatekeeper 판정. 통과하면 이상하고, 실패가 정상이다.
if spctl --assess --type execute "$MNT/SysWatt.app" >/dev/null 2>&1; then
    echo "ℹ️ Gatekeeper 통과 (Developer ID 로 서명·공증된 상태로 보인다)"
else
    echo "ℹ️ Gatekeeper 거부 (ad-hoc 서명이라 정상). 받는 사람 안내는 README 참조."
fi

(cd dist && shasum -a 256 "${NAME}.dmg" >"${NAME}.dmg.sha256")
# 정리 전에 내린다. 마운트된 지점을 rm 하면 read-only 파일시스템이라고 터진다.
cleanup
rm -rf "$STAGE" "$MNT"

ls -lh "$DMG" | awk '{print "📄 " $5 "  " $9}'
cat "$DMG.sha256"
