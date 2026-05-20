import SwiftUI
import SharedKit

struct MenuBarView: View {
    @EnvironmentObject var store: MailStore
    @EnvironmentObject var updater: UpdateChecker
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MailSorter")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(store.isDaemonRunning ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(store.isDaemonRunning ? "데몬 실행 중" : "데몬 중지됨")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 8)

                if store.isFetching {
                    ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
                } else {
                    Button {
                        store.fetchAndRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("새로고침")
                }
            }

            if let lastSync = store.lastSyncedAt {
                Text("마지막 동기화: \(lastSync, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if updater.updateAvailable, let latest = updater.latestVersion {
                Divider()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(UpdateChecker.installCommand, forType: .string)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("v\(latest) 업데이트 있음")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.blue)
                            Text("클릭 → 설치 명령어 복사")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            ForEach(MailLabel.allCases, id: \.self) { label in
                HStack {
                    Image(systemName: label.sfSymbol)
                        .foregroundStyle(label.color)
                        .frame(width: 18)
                    Text(label.displayName)

                    Spacer()

                    let unread = store.unreadCounts[label] ?? 0
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(label.color)
                            .clipShape(Capsule())
                            .padding(.trailing, 4)
                    }

                    Text("\(store.counts[label] ?? 0)")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    store.filter = label
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }

            Divider()

            Button("메일함 열기") {
                store.filter = nil
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("환경설정...") {
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: [.command])

            Button("MailSorter 종료") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(12)
    }
}
