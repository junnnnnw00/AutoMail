# AutoMail

학교 IMAP 메일을 4단계(중요/일반/교내회보/광고)로 자동 분류하는 macOS 네이티브 메뉴바 앱 + 백그라운드 데몬.

> **요구사항**: macOS 14.0+, Apple Silicon (arm64)

<img width="381" height="297" alt="Screenshot 2026-05-21 at 10 43 42 AM" src="https://github.com/user-attachments/assets/898ef0d4-c543-434d-93e7-690215f7eaa8" />
<img width="1372" height="934" alt="Screenshot 2026-05-21 at 10 43 15 AM" src="https://github.com/user-attachments/assets/9d92d8b5-6a45-4a37-b9ce-d25e02aad278" />

## 설치

### 권장 — 자동 설치

```bash
curl -fsSL https://raw.githubusercontent.com/junnnnnw00/AutoMail/main/Scripts/install.sh | bash
```

다운로드 → `~/Applications` 이동 → Gatekeeper 해제까지 자동. macOS 14+, Apple Silicon 전용.

### 수동 설치

1. [Releases](../../releases/latest)에서 `MailSorter-*.zip` 다운로드
2. 압축 해제 후 `MailSorter.app`을 `~/Applications`로 이동
3. 터미널에서 Gatekeeper 해제:
   ```bash
   xattr -dr com.apple.quarantine ~/Applications/MailSorter.app
   ```
4. 앱 실행 → 메뉴바 우측 트레이 아이콘 확인

---

## 계정 연결 (처음 한 번)

### 1단계 — 학교 메일(Outlook) → Gmail 자동 전달 설정

1. [Outlook 웹](https://outlook.office.com) 로그인
2. 우측 상단 ⚙️ → **메일 → 전달** (또는 직접: [outlook.office.com/mail/options/mail/forwarding](https://outlook.office.com/mail/options/mail/forwarding))
3. **전달 사용** 체크 → Gmail 주소 입력 → 저장

> 학교에서 외부 전달을 막아 둔 경우 IT 담당자에게 문의하거나, 학교 웹메일의 IMAP을 직접 사용하세요.

### 2단계 — Gmail 앱 비밀번호 발급

AutoMail은 일반 Google 비밀번호 대신 **앱 비밀번호** (16자리)를 사용합니다.

1. [Google 앱 비밀번호 페이지](https://myaccount.google.com/apppasswords) 이동 (2단계 인증이 켜져 있어야 접근 가능)
2. 앱 이름 입력 (예: `AutoMail`) → **만들기**
3. 표시되는 **16자리 코드** 복사 (띄어쓰기 없이)

> 2단계 인증이 꺼져 있으면 [여기서 먼저 활성화](https://myaccount.google.com/signinoptions/twosv).

### 3단계 — AutoMail에 계정 등록

메뉴바 아이콘 → **환경설정 → 계정 탭**

| 항목 | 값 |
|---|---|
| 서버 | `imap.gmail.com` |
| 포트 | `993` |
| TLS | ON |
| 이메일 | Gmail 주소 |
| 앱 비밀번호 | 2단계에서 발급한 16자리 |

→ **저장 + 키체인 등록** → **연결 테스트** 로 확인

### 4단계 — 자동시작 설정

환경설정 → **데몬 탭** → 로그인 시 자동 시작 ON

## 기능

- **백그라운드 분류**: LaunchAgent 데몬이 IMAP으로 실시간 메일 수신, 자동 라벨링 + 폴더 이동
- **GUI**: 메뉴바 아이콘 클릭으로 라벨별 카운트 확인, 메인 윈도우에서 메일 리스트/상세/검색
- **키보드 단축키**: ⌘F 검색 포커스, ⌘R 새로고침, Delete 삭제, ↑↓ 탐색
- **피드백 학습**: 라벨 수정 시 `feedback_queue` 누적 → 임계치 도달 시 CreateML 자동 재학습
- **일일 다이제스트**: 지정 시각에 직전 24h 중요 메일 알림
- **자동시작**: 로그인 시 데몬 자동 기동

## 분류 동작

1. 정규식 규칙 우선 매칭 (교내회보/광고/중요 키워드)
2. 미매칭 시 NLModel (CreateML) 추론
3. 초기엔 모델 없음 → 룰 미매칭은 일반으로 폴백
4. 사용자 라벨 수정 누적 → 자동 재학습

## 소스 빌드

```bash
# 요구사항: macOS 14+, Swift 6 / Xcode 15+
./Scripts/build_app.sh
open ~/Applications/MailSorter.app
```

## 릴리즈 배포 (maintainer)

```bash
# gh CLI 필요: brew install gh && gh auth login
./Scripts/release.sh v0.2.0

# 릴리즈 노트 직접 지정
./Scripts/release.sh v0.2.0 "버그 수정: ..."
```

빌드 → .app 패키징 → GitHub Release 생성까지 자동으로 처리.

## 디렉토리 구조

```
AutoMail/
├── Package.swift
├── Sources/
│   ├── SharedKit/          # 모델, DB, 분류기, 트레이너, 키체인, 알림
│   ├── MailSorterDaemon/   # LaunchAgent 백그라운드 데몬
│   └── MailSorterApp/      # SwiftUI 메뉴바 앱
├── Tests/SharedKitTests/
└── Scripts/build_app.sh
```

## 데이터 저장 위치

| 파일 | 경로 |
|---|---|
| SQLite DB | `~/Library/Application Support/MailSorter/mailsorter.sqlite` |
| 학습된 모델 | `~/Library/Application Support/MailSorter/classifier.mlmodel(c)` |
| LaunchAgent plist | `~/Library/LaunchAgents/com.junwoo.mailsorter.daemon.plist` |
| 데몬 로그 | `~/Library/Logs/MailSorter/daemon.{log,err}` |
| IMAP 자격 | macOS 키체인 (`com.junwoo.mailsorter`) |

## 데몬 진단

```bash
launchctl print "gui/$UID/com.junwoo.mailsorter.daemon"
log stream --predicate 'subsystem == "com.junwoo.mailsorter"'
```

## 알려진 제한

- Apple Silicon 전용 (arm64)
- IMAP 클라이언트 미니멀 구현 (멀티파트 MIME 일부 한정)
- 멀티 계정 미지원
- 데몬이 꺼져 있으면 일일 다이제스트 발송 안 됨
