import SwiftUI
import SharedKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var store: MailStore
    @State private var accountStatus: String?
    @State private var notifyStatus: String?
    @State private var classifierStatus: String?
    @State private var daemonStatus: String?
    @State private var saving = false
    @State private var testingConnection = false
    @State private var isTraining = false
    @State private var launchAgentEnabled = LaunchAgentInstaller.isRegistered
    @State private var appLoginItemEnabled = LaunchAgentInstaller.isAppLoginItemRegistered

    var body: some View {
        TabView {
            accountTab.tabItem { Label("계정", systemImage: "person.crop.circle") }
            notificationTab.tabItem { Label("알림", systemImage: "bell") }
            classifierTab.tabItem { Label("분류", systemImage: "brain") }
            statsTab.tabItem { Label("통계", systemImage: "chart.bar") }
            daemonTab.tabItem { Label("데몬", systemImage: "gear") }
        }
        .frame(width: 580, height: 500)
    }

    // MARK: - Account

    private var accountTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Info banner
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("학교 메일을 개인 Gmail로 자동 전달한 뒤 아래 Gmail 계정을 연결하세요.\n'Google 계정 관리 > 보안 > 2단계 인증 > 앱 비밀번호'에서 16자리 비밀번호를 발급받으세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                GroupBox("서버") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("서버 (예: imap.gmail.com)", text: $settings.imapHost)
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 12) {
                            TextField("포트", value: $settings.imapPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Toggle("TLS 사용", isOn: $settings.imapUseTLS)
                            Spacer()
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("계정") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("이메일 주소 (@gmail.com)", text: $settings.imapUsername)
                            .textFieldStyle(.roundedBorder)
                        SecureField("앱 비밀번호 (16자리, 띄어쓰기 없이)", text: $settings.imapPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 4)
                }

                HStack(spacing: 8) {
                    Button("저장 + 키체인 등록") { saveCredentials() }
                        .disabled(saving || testingConnection)
                    Button("연결 테스트") { testConnection() }
                        .disabled(testingConnection || settings.imapHost.isEmpty
                                  || settings.imapUsername.isEmpty || settings.imapPassword.isEmpty)
                    if testingConnection { ProgressView().scaleEffect(0.7) }
                    Spacer()
                }

                if let accountStatus {
                    Text(accountStatus)
                        .font(.caption)
                        .foregroundStyle(statusColor(accountStatus))
                }
            }
            .padding(16)
        }
    }

    // MARK: - Notifications

    private var notificationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("알림 설정") {
                    VStack(alignment: .leading, spacing: 10) {
                        DatePicker("일일 다이제스트 시각", selection: $settings.digestTime,
                                   displayedComponents: .hourAndMinute)
                        Toggle("중요 메일 도착 즉시 알림", isOn: $settings.immediateImportantAlerts)
                    }
                    .padding(.top, 4)
                }

                HStack(spacing: 8) {
                    Button("알림 권한 요청") {
                        Task { await NotificationCenterClient.shared.requestAuthorization() }
                    }
                    Button("저장") {
                        settings.savePrefs()
                        notifyStatus = "저장됨"
                    }
                    Spacer()
                }

                if let notifyStatus {
                    Text(notifyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Classifier

    private var classifierTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("자동 학습") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("재학습 임계: 라벨 \(settings.retrainThreshold)건",
                                value: $settings.retrainThreshold, in: 5...200, step: 5)
                        HStack(spacing: 8) {
                            TextField("교내회보 폴더명", text: $settings.folderNewsletter)
                                .textFieldStyle(.roundedBorder)
                            TextField("광고 폴더명", text: $settings.folderAd)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("라벨 결과에 따라 지정 폴더로 자동 이동 (없으면 자동 생성)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                HStack(spacing: 8) {
                    Button("저장") {
                        settings.savePrefs()
                        classifierStatus = "저장됨"
                    }
                    Button("지금 재학습") { retrain() }
                        .disabled(isTraining)
                    if isTraining {
                        ProgressView().scaleEffect(0.7)
                        Text("학습 중...").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if !isTraining, let classifierStatus {
                    Text(classifierStatus)
                        .font(.caption)
                        .foregroundStyle(statusColor(classifierStatus))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Stats

    private var statsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s = store.classifierStats {
                    GroupBox("모델 상태") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: s.modelExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(s.modelExists ? .green : .red)
                                Text(s.modelExists ? "학습된 모델 존재" : "모델 없음 (규칙 전용)")
                            }
                            if let trained = s.lastTrainedAt {
                                Text("마지막 학습: \(trained.formatted(date: .abbreviated, time: .shortened))")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("학습 이력 없음").foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                        .padding(.top, 4)
                    }

                    GroupBox("분류 정확도") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("자동 분류 유지율")
                                Spacer()
                                Text(String(format: "%.1f%%", s.autoAccuracyRate * 100))
                                    .bold()
                                    .foregroundStyle(s.autoAccuracyRate >= 0.8 ? .green : s.autoAccuracyRate >= 0.6 ? .orange : .red)
                            }
                            HStack {
                                Text("사용자 수정")
                                Spacer()
                                Text("\(s.userOverrideCount) / \(s.totalMails)건")
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("미소비 피드백")
                                Spacer()
                                Text("\(s.pendingFeedback)건")
                                    .foregroundStyle(s.pendingFeedback > 0 ? .orange : .secondary)
                            }
                        }
                        .font(.callout)
                        .padding(.top, 4)
                    }

                    GroupBox("라벨 분포") {
                        VStack(spacing: 4) {
                            ForEach(MailLabel.allCases, id: \.self) { label in
                                let count = s.labelCounts[label] ?? 0
                                let pct = s.totalMails > 0 ? Double(count) / Double(s.totalMails) : 0
                                HStack(spacing: 8) {
                                    Text(label.displayName).frame(width: 60, alignment: .leading)
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.accentColor.opacity(0.25))
                                            .frame(width: geo.size.width * pct)
                                    }
                                    .frame(height: 14)
                                    Text("\(count)").foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                                }
                            }
                        }
                        .font(.callout)
                        .padding(.top, 4)
                    }

                    GroupBox("분류 출처") {
                        VStack(spacing: 4) {
                            ForEach(["model", "combined", "rule", "fallback", "unknown"], id: \.self) { src in
                                let count = s.sourceCounts[src] ?? 0
                                guard count > 0 else { return AnyView(EmptyView()) }
                                return AnyView(HStack {
                                    Text(sourceLabel(src))
                                    Spacer()
                                    Text("\(count)건").foregroundStyle(.secondary)
                                })
                            }
                        }
                        .font(.callout)
                        .padding(.top, 4)
                    }
                } else {
                    ProgressView("통계 로딩 중...")
                }
            }
            .padding(16)
        }
    }

    private func sourceLabel(_ src: String) -> String {
        switch src {
        case "model":    return "ML 모델"
        case "combined": return "모델 + 규칙"
        case "rule":     return "규칙 전용"
        case "fallback": return "폴백 (모델 없음)"
        default:         return "알 수 없음 (구버전)"
        }
    }

    // MARK: - Daemon

    private var daemonTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("데몬 (백그라운드 메일 수신)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("로그인 시 데몬 자동 시작", isOn: $launchAgentEnabled)
                            .onChange(of: launchAgentEnabled) { _, newValue in
                                do {
                                    if newValue { try LaunchAgentInstaller.register() }
                                    else { try LaunchAgentInstaller.unregister() }
                                    daemonStatus = newValue ? "데몬 등록됨" : "데몬 해제됨"
                                } catch {
                                    daemonStatus = "실패: \(error.localizedDescription)"
                                    launchAgentEnabled = LaunchAgentInstaller.isRegistered
                                }
                            }
                        Text(LaunchAgentInstaller.plistURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 4)
                }

                GroupBox("앱 (메뉴바)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("로그인 시 앱 자동 시작", isOn: $appLoginItemEnabled)
                            .onChange(of: appLoginItemEnabled) { _, newValue in
                                do {
                                    if newValue { try LaunchAgentInstaller.registerAppLoginItem() }
                                    else { try LaunchAgentInstaller.unregisterAppLoginItem() }
                                    daemonStatus = newValue ? "앱 로그인 항목 등록됨" : "앱 로그인 항목 해제됨"
                                } catch {
                                    daemonStatus = "실패: \(error.localizedDescription)"
                                    appLoginItemEnabled = LaunchAgentInstaller.isAppLoginItemRegistered
                                }
                            }
                        Text("독 아이콘: 앱 실행 후 독에서 우클릭 → 옵션 → Dock에 유지")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                if let daemonStatus {
                    Text(daemonStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func retrain() {
        isTraining = true
        classifierStatus = nil
        Task {
            do {
                _ = try await Trainer().trainIfReady()
                classifierStatus = "✓ 재학습 완료"
                EventBus.post(.modelReloaded)
            } catch TrainerError.notEnoughSamples(let count) {
                classifierStatus = "✗ 샘플 부족 (\(count)개 / 최소 20개 필요)"
            } catch {
                classifierStatus = "✗ 실패: \(error.localizedDescription)"
            }
            isTraining = false
        }
    }

    private func saveCredentials() {
        saving = true
        do {
            try settings.saveCredentials()
            accountStatus = "✓ 키체인 저장 완료"
        } catch {
            accountStatus = "✗ 오류: \(error.localizedDescription)"
        }
        saving = false
    }

    private func testConnection() {
        testingConnection = true
        accountStatus = "연결 중..."
        let creds = IMAPCredentials(
            host: settings.imapHost,
            port: settings.imapPort,
            useTLS: settings.imapUseTLS,
            username: settings.imapUsername,
            password: settings.imapPassword
        )
        Task {
            do {
                let client = IMAPClient(creds: creds)
                defer {
                    client.cancel()
                }
                try await client.connect()
                try await client.login()
                await client.disconnect()
                accountStatus = "✓ 연결 성공"
            } catch {
                accountStatus = "✗ 실패: \(error.localizedDescription)"
            }
            testingConnection = false
        }
    }

    private func statusColor(_ text: String) -> Color {
        if text.hasPrefix("✓") { return .green }
        if text.hasPrefix("✗") { return .red }
        return .secondary
    }
}
