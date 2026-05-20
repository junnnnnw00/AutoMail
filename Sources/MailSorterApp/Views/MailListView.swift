import SwiftUI
import SharedKit

struct MailListView: View {
    @EnvironmentObject var store: MailStore
    @State private var selection: Set<Mail.ID> = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("필터", selection: $store.filter) {
                    Text("전체").tag(MailLabel?.none)
                    ForEach(MailLabel.allCases, id: \.self) { label in
                        let unread = store.unreadCounts[label] ?? 0
                        Text(unread > 0 ? "\(label.displayName) (\(unread))" : label.displayName).tag(MailLabel?.some(label))
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)

                TextField("제목, 보낸사람, 본문 검색", text: $store.search)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)

                if !store.isModelTrained {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("분류 모델 미학습 — 라벨을 충분히 지정한 뒤 설정 > 분류 > 지금 재학습 하세요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                }

                List(selection: $selection) {
                    ForEach(store.visibleMails) { mail in
                        MailRow(mail: mail)
                            .tag(mail.id)
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand {
                    guard !selection.isEmpty else { return }
                    store.deleteMails(ids: selection)
                    selection.removeAll()
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 360)
            .onChange(of: store.filter) { _, _ in selection.removeAll() }
            .onChange(of: store.search) { _, _ in selection.removeAll() }
            .background(
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            )
        } detail: {
            if let firstSelected = selection.first, selection.count == 1, let mail = store.visibleMails.first(where: { $0.id == firstSelected }) {
                MailDetailView(mail: mail)
            } else if selection.count > 1 {
                ContentUnavailableView(
                    "\(selection.count)개의 메일 선택됨",
                    systemImage: "tray.2",
                    description: Text("Delete 키로 삭제, 툴바 태그 메뉴로 라벨 일괄 변경")
                )
            } else {
                ContentUnavailableView(
                    "메일을 선택하세요",
                    systemImage: "envelope",
                    description: Text("↑↓로 탐색  ⌘F 검색  ⌘R 새로고침  Delete 삭제")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(store.isDaemonRunning ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(store.isDaemonRunning ? "데몬 실행 중" : "데몬 중지됨")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider().frame(height: 12)

                    if store.isFetching {
                        ProgressView().scaleEffect(0.6)
                        Text("동기화 중...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let err = store.fetchError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else if let lastSync = store.lastSyncedAt {
                        Text("마지막 동기화: \(lastSync, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    if !selection.isEmpty {
                        Menu {
                            Menu("라벨 추가") {
                                ForEach(MailLabel.allCases, id: \.self) { label in
                                    Button(label.displayName) {
                                        for id in selection {
                                            if let m = store.mails.first(where: { $0.id == id }) {
                                                if label == .normal {
                                                    store.relabel(mail: m, to: [.normal])
                                                } else {
                                                    var newLabels = m.labels
                                                    newLabels.insert(label)
                                                    if newLabels.count > 1 {
                                                        newLabels.remove(.normal)
                                                    }
                                                    store.relabel(mail: m, to: newLabels)
                                                }
                                            }
                                        }
                                        selection.removeAll()
                                    }
                                }
                            }
                            Menu("라벨 제거") {
                                ForEach(MailLabel.allCases, id: \.self) { label in
                                    Button(label.displayName) {
                                        for id in selection {
                                            if let m = store.mails.first(where: { $0.id == id }) {
                                                var newLabels = m.labels
                                                newLabels.remove(label)
                                                if newLabels.isEmpty {
                                                    newLabels.insert(.normal)
                                                }
                                                store.relabel(mail: m, to: newLabels)
                                            }
                                        }
                                        selection.removeAll()
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "tag")
                        }
                        .help("선택한 메일 라벨 추가/제거")

                        Button {
                            store.deleteMails(ids: selection)
                            selection.removeAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("선택한 메일 삭제 (Delete)")
                    }

                    Button {
                        store.fetchAndRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isFetching)
                    .help("IMAP 수신 후 새로고침 (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
    }
}

struct MailRow: View {
    @EnvironmentObject var store: MailStore
    let mail: Mail

    var body: some View {
        let primary = mail.labels.primaryLabel()
        let nonPrimaryLabels = Array(mail.labels)
            .filter { $0 != primary }
            .sorted(by: { $0.rawValue < $1.rawValue })

        HStack(alignment: .top) {
            Circle()
                .fill(mail.seenAt == nil ? Color.blue : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
                .padding(.trailing, 2)

            Image(systemName: primary.sfSymbol)
                .foregroundStyle(primary.color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(mail.subject)
                    .font(.system(size: 13, weight: mail.seenAt == nil ? .bold : .regular))
                    .lineLimit(1)
                Text(mail.fromName ?? mail.fromAddress)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(relativeDateString(mail.receivedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if !nonPrimaryLabels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(nonPrimaryLabels, id: \.self) { label in
                            Text(label.displayName)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(label.color.opacity(0.12))
                                .foregroundStyle(label.color)
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .contextMenu {
            ForEach(MailLabel.allCases, id: \.self) { label in
                Button {
                    store.toggleLabel(mail: mail, label: label)
                } label: {
                    Label(label.displayName, systemImage: mail.labels.contains(label) ? "checkmark" : label.sfSymbol)
                }
            }
        }
    }

    private func relativeDateString(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "어제"
        } else if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
