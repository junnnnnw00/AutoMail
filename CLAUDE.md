# AutoMail — CLAUDE.md

## 프로젝트 구조

Swift Package Manager 멀티타겟. Xcode 프로젝트 없음.

```
Sources/
  SharedKit/        # 공유 모델/서비스 (데몬+앱 양쪽 import)
  MailSorterDaemon/ # LaunchAgent 백그라운드 프로세스
  MailSorterApp/    # SwiftUI 메뉴바 앱
Tests/SharedKitTests/
Scripts/
  build_app.sh      # 릴리즈 빌드 → ~/Applications/MailSorter.app
  release.sh        # build_app.sh + zip + gh release create
  install.sh        # 유저용 원클릭 설치/업데이트
```

## 빌드 & 실행

```bash
swift build                    # 디버그 (전체)
swift build -c release         # 릴리즈
swift test                     # 테스트

.build/debug/MailSorterApp     # GUI 앱 직접 실행
.build/debug/MailSorterDaemon  # 데몬 포그라운드 실행

./Scripts/build_app.sh         # 릴리즈 빌드 → .app 번들
./Scripts/release.sh v0.x.x    # GitHub Release까지 자동
```

## 핵심 아키텍처

### 데이터 흐름
```
IMAP → MailIngestor → NLClassifier/Rules → Database (GRDB/SQLite)
                                         → IMAP 폴더 이동
MailSorterApp → MailStore (DB 읽기) → SwiftUI
```

### 프로세스 간 통신
`DistributedNotificationCenter` (Darwin 알림). `EventBus` in `SharedKit/Services/Events.swift`.
이벤트: `newMail`, `modelReloaded`, `labelChanged`, `daemonHeartbeat`.

### 데이터 저장
- SQLite: `~/Library/Application Support/MailSorter/mailsorter.sqlite` (GRDB)
- 설정: `UserDefaults(suiteName: "com.junwoo.mailsorter.shared")`
- IMAP 자격: macOS 키체인 (`KeychainStore`)
- ML 모델: `~/Library/Application Support/MailSorter/classifier.mlmodel(c)`

## 핵심 파일

| 파일 | 역할 |
|---|---|
| `SharedKit/Services/Database.swift` | GRDB 풀, 스키마, 쿼리 |
| `SharedKit/Services/NLClassifier.swift` | Rules + NLModel 분류. 규칙 우선, 미매칭 시 ML |
| `SharedKit/Services/Rules.swift` | 정규식 분류 규칙. `Pattern.id`는 UUID (안정적 identity) |
| `SharedKit/Services/MailIngestor.swift` | IMAP fetch → 분류 → DB 저장 → 폴더 이동 |
| `SharedKit/Services/Trainer.swift` | CreateML 재학습. `feedback_queue` 임계치 초과 시 실행 |
| `MailSorterApp/Services/MailStore.swift` | SwiftUI ObservableObject. DB → UI 브릿지 |
| `MailSorterApp/Services/UpdateChecker.swift` | GitHub releases API 버전 체크 |
| `MailSorterApp/App.swift` | Scene 설정. `AppDelegate.openMainWindow` 클로저로 독 클릭 처리 |

## 라벨 시스템

`MailLabel`: `important`, `normal`, `newsletter`, `ad`

**핵심 규칙**: `normal`은 다른 라벨과 상호 배타적.
- 비어있으면 → `normal` 자동 삽입
- `normal` + 다른 라벨 → `normal` 제거
- **`toggleLabel`에서 `.normal` 클릭 시**: 다른 라벨 전부 지우고 `[.normal]` 단독 설정 (이 처리 없으면 `count>1` 로직에 걸려서 `.normal`이 다시 제거됨 — 과거 버그)

## 독 아이콘 → 메인 윈도우 열기

`applicationShouldHandleReopen` → `AppDelegate.openMainWindow?()`.
`openMainWindow`는 `App.body` 평가 시점에 `@Environment(\.openWindow)` 캡처해서 주입.
MenuBarExtra content는 lazy라서 NotificationCenter 방식 사용 불가 (첫 팝오버 전엔 뷰 미생성).

## 설정 UI 주의사항

- `SettingsView` frame: `TabView`에 `.frame(width: 580, height: 500)` — `App.swift`에 별도 frame 없음
- Form 내부 TextField에 `.labelsHidden()` 필요 (macOS Form이 label 컬럼 처리 적용)
- `Rules.Pattern`은 UUID 기반 id (`ForEach($settings.rulesPatterns)` 사용 가능)

## 릴리즈 프로세스

1. `./Scripts/release.sh v0.x.x` — 빌드 + zip + GitHub release
2. `build_app.sh`의 `CFBundleShortVersionString`도 함께 업데이트할 것
3. `UpdateChecker`가 GitHub releases latest tag와 비교하므로 tag 형식은 `v0.x.x` 유지

## 테스트

```bash
swift test
# Tests/SharedKitTests/MailLabelTests.swift — 라벨 로직
# Tests/SharedKitTests/RulesTests.swift     — 정규식 매칭
```

## 알려진 제약

- Apple Silicon (arm64) 전용. Intel 지원 필요 시 `lipo` universal binary 빌드 추가 필요
- IMAP 클라이언트 (`IMAPClient.swift`) 미니멀 구현 — 멀티파트 MIME 일부 한정
- 앱 비서명 (ad-hoc `--sign -`) → 배포 시 `xattr -dr com.apple.quarantine` 필요
- 멀티 계정 미지원
