#!/bin/bash
set -euo pipefail

# Usage: ./Scripts/release.sh v0.2.0 ["release notes"]
VERSION="${1:-}"
NOTES="${2:-}"

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version> [\"release notes\"]" >&2
    echo "  e.g. $0 v0.2.0" >&2
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI not found. Install: brew install gh" >&2
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "Error: not logged in to GitHub. Run: gh auth login" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

echo "▶︎ Building release binary..."
./Scripts/build_app.sh

ZIP="/tmp/MailSorter-${VERSION}.zip"
APP="$HOME/Applications/MailSorter.app"

echo "▶︎ Packaging ${ZIP}..."
rm -f "$ZIP"
cd "$(dirname "$APP")"
zip -r "$ZIP" "$(basename "$APP")"
cd - >/dev/null

DEFAULT_NOTES="## AutoMail ${VERSION}

### 설치
1. \`MailSorter-${VERSION}.zip\` 다운로드 후 압축 해제
2. \`MailSorter.app\`을 \`/Applications\` 또는 \`~/Applications\`로 이동
3. Gatekeeper 우회 (미서명 앱, 최초 1회):
   \`\`\`bash
   xattr -dr com.apple.quarantine /Applications/MailSorter.app
   \`\`\`
4. 앱 실행 → 메뉴바 아이콘 확인

### 요구사항
- macOS 14.0+, Apple Silicon (arm64)"

echo "▶︎ Creating GitHub release ${VERSION}..."
gh release create "$VERSION" "$ZIP" \
    --title "${VERSION}" \
    --notes "${NOTES:-$DEFAULT_NOTES}"

echo ""
echo "✓ Released: $(gh release view "$VERSION" --json url -q .url)"
