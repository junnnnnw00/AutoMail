#!/bin/bash
set -euo pipefail

REPO="junnnnnw00/AutoMail"
APP_NAME="MailSorter"
INSTALL_DIR="$HOME/Applications"

IS_UPDATE=false
[[ -d "$INSTALL_DIR/${APP_NAME}.app" ]] && IS_UPDATE=true
ACTION=$( $IS_UPDATE && echo "업데이트" || echo "설치" )
echo "▶︎ AutoMail ${ACTION} 시작..."

# Check macOS version
OS_VER=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$OS_VER" -lt 14 ]]; then
    echo "Error: macOS 14.0 이상 필요 (현재: $(sw_vers -productVersion))" >&2
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    echo "Error: Apple Silicon(arm64) 전용입니다 (현재: $ARCH)" >&2
    exit 1
fi

# Get latest release download URL
echo "▶︎ 최신 릴리즈 확인 중..."
DOWNLOAD_URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"browser_download_url"' \
    | grep '\.zip"' \
    | head -1 \
    | sed 's/.*"browser_download_url": "\(.*\)"/\1/')

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo "Error: 릴리즈를 찾을 수 없습니다." >&2
    exit 1
fi

ZIP_NAME=$(basename "$DOWNLOAD_URL")
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Download
echo "▶︎ 다운로드 중: $ZIP_NAME"
curl -fsSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/$ZIP_NAME"

# Extract
echo "▶︎ 압축 해제 중..."
unzip -q "$TMP_DIR/$ZIP_NAME" -d "$TMP_DIR"

# Install
mkdir -p "$INSTALL_DIR"
if [[ -d "$INSTALL_DIR/${APP_NAME}.app" ]]; then
    echo "▶︎ 기존 버전 교체 중..."
    rm -rf "$INSTALL_DIR/${APP_NAME}.app"
fi
cp -R "$TMP_DIR/${APP_NAME}.app" "$INSTALL_DIR/"

# Remove quarantine
echo "▶︎ Gatekeeper 제한 해제 중..."
xattr -dr com.apple.quarantine "$INSTALL_DIR/${APP_NAME}.app" 2>/dev/null || true

echo ""
echo "✓ ${ACTION} 완료: $INSTALL_DIR/${APP_NAME}.app"
echo ""
if ! $IS_UPDATE; then
    echo "초기 설정:"
    echo "  1. 메뉴바 아이콘 → 환경설정 → 계정 탭"
    echo "  2. IMAP 서버/이메일/앱 비밀번호 입력 후 저장"
    echo "  3. 데몬 탭 → '로그인 시 자동 시작' ON"
    echo ""
fi

read -r -p "지금 실행하시겠습니까? [Y/n] " REPLY
REPLY="${REPLY:-Y}"
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    open "$INSTALL_DIR/${APP_NAME}.app"
fi
