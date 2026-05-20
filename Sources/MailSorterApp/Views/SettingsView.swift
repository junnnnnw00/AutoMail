import SwiftUI
import SharedKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var accountStatus: String?
    @State private var notifyStatus: String?
    @State private var classifierStatus: String?
    @State private var daemonStatus: String?
    @State private var saving = false
    @State private var testingConnection = false
    @State private var launchAgentEnabled = LaunchAgentInstaller.isRegistered
    @State private var appLoginItemEnabled = LaunchAgentInstaller.isAppLoginItemRegistered

    var body: some View {
        TabView {
            accountTab.tabItem { Label("계정", systemImage: "person.crop.circle") }
            notificationTab.tabItem { Label("알림", systemImage: "bell") }
            classifierTab.tabItem { Label("분류", systemImage: "brain") }
            daemonTab.tabItem { Label("데몬", systemImage: "gear") }
        }
        .frame(width: 580, height: 500)
    }

    private var accountTab: some View {
        Form {
            Section("Gmail IMAP 설정") {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 14))
                    Text("학교 메일을 개인 Gmail로 자동 전달한 뒤, 아래에 Gmail 계정을 연결하세요.\n로그인을 위해 'Google 계정 관리 > 보안 > 2단계 인증 > 앱 비밀번호'에서 16자리 비밀번호를 발급받아야 합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.06))
                .cornerRadius(6)
                .padding(.bottom, 5)

                TextField("서버", text: $settings.imapHost)
                HStack {
                    TextField("포트", value: $settings.imapPort, format: .number)
                        .frame(width: 80)
                    Toggle("TLS 사용", isOn: $settings.imapUseTLS)
                }
                TextField("이메일 주소 (@gmail.com 포함)", text: $settings.imapUsername)
                SecureField("앱 비밀번호 (16자리 띄어쓰기 없이)", text: $settings.imapPassword)
                HStack {
                    Button("저장 + 키체인 등록") { saveCredentials() }
                        .disabled(saving || testingConnection)
                    Button("연결 테스트") { testConnection() }
                        .disabled(testingConnection || settings.imapHost.isEmpty || settings.imapUsername.isEmpty || settings.imapPassword.isEmpty)
                    if testingConnection {
                        ProgressView().scaleEffect(0.7)
                    } else if let accountStatus {
                        Text(accountStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var notificationTab: some View {
        Form {
            DatePicker("일일 다이제스트 시각", selection: $settings.digestTime, displayedComponents: .hourAndMinute)
            Toggle("중요 메일 도착 즉시 알림", isOn: $settings.immediateImportantAlerts)
            Button("권한 요청") {
                Task {
                    await NotificationCenterClient.shared.requestAuthorization()
                }
            }
            HStack {
                Button("저장") {
                    settings.savePrefs()
                    notifyStatus = "저장됨"
                }
                if let notifyStatus {
                    Text(notifyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var classifierTab: some View {
        Form {
            Section("자동 학습 설정") {
                Stepper("재학습 임계 (라벨 \(settings.retrainThreshold)건)", value: $settings.retrainThreshold, in: 5...200, step: 5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("교내회보 폴더명", text: $settings.folderNewsletter)
                        TextField("광고 폴더명", text: $settings.folderAd)
                    }
                    Text("라벨 분류 결과에 따라 지정된 폴더로 메일이 자동 이동됩니다. (지정한 폴더가 사서함에 없는 경우 자동으로 생성됩니다.)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

HStack {
                Button("저장") {
                    settings.savePrefs()
                    classifierStatus = "저장됨"
                }
                Button("지금 재학습") {
                    Task {
                        do {
                            _ = try await Trainer().trainIfReady()
                            classifierStatus = "재학습 완료"
                            EventBus.post(.modelReloaded)
                        } catch TrainerError.notEnoughSamples(let count) {
                            classifierStatus = "샘플 부족 (\(count))"
                        } catch {
                            classifierStatus = "실패: \(error.localizedDescription)"
                        }
                    }
                }
                if let classifierStatus {
                    Text(classifierStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var daemonTab: some View {
        Form {
            Section("데몬 (메일 수신)") {
                Toggle("로그인 시 데몬 자동 시작", isOn: $launchAgentEnabled)
                    .onChange(of: launchAgentEnabled) { _, newValue in
                        do {
                            if newValue {
                                try LaunchAgentInstaller.register()
                            } else {
                                try LaunchAgentInstaller.unregister()
                            }
                            daemonStatus = newValue ? "데몬 등록됨" : "데몬 해제됨"
                        } catch {
                            daemonStatus = "실패: \(error.localizedDescription)"
                            launchAgentEnabled = LaunchAgentInstaller.isRegistered
                        }
                    }
                Text("LaunchAgent: \(LaunchAgentInstaller.plistURL.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("앱 (메뉴바)") {
                Toggle("로그인 시 앱 자동 시작", isOn: $appLoginItemEnabled)
                    .onChange(of: appLoginItemEnabled) { _, newValue in
                        do {
                            if newValue {
                                try LaunchAgentInstaller.registerAppLoginItem()
                            } else {
                                try LaunchAgentInstaller.unregisterAppLoginItem()
                            }
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

            if let daemonStatus {
                Text(daemonStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func saveCredentials() {
        saving = true
        do {
            try settings.saveCredentials()
            accountStatus = "키체인 저장 완료"
        } catch {
            accountStatus = "오류: \(error.localizedDescription)"
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
}
