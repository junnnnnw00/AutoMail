import Foundation
import Combine
import SharedKit

@MainActor
public final class MailStore: ObservableObject {
    @Published public private(set) var mails: [Mail] = []
    @Published public private(set) var counts: [MailLabel: Int] = [:]
    @Published public private(set) var unreadCounts: [MailLabel: Int] = [:]
    @Published public var filter: MailLabel? = nil
    @Published public var search: String = ""
    @Published public private(set) var isFetching = false
    @Published public private(set) var fetchError: String?
    @Published public private(set) var lastSyncedAt: Date?
    @Published public private(set) var isDaemonRunning = false

    private var observers: [NSObjectProtocol] = []
    private var pollingTimer: Timer?
    private var autoFetchTimer: Timer?
    private var lastDaemonHeartbeat: Date?

    public var isModelTrained: Bool {
        FileManager.default.fileExists(atPath: AppPaths.compiledClassifierURL.path)
    }

    public init() {
        observers.append(EventBus.observe(.newMail) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(EventBus.observe(.modelReloaded) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(EventBus.observe(.labelChanged) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(EventBus.observe(.daemonHeartbeat) { [weak self] _ in
            Task { @MainActor in
                self?.lastDaemonHeartbeat = Date()
                self?.isDaemonRunning = true
            }
        })
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                let now = Date()
                let daemonAlive = self?.lastDaemonHeartbeat.map { now.timeIntervalSince($0) < 25 } ?? false
                if !daemonAlive {
                    self?.isDaemonRunning = false
                    self?.fetchAndRefresh()
                }
            }
        }
        // Safety-net IMAP fetch every 60 seconds regardless of daemon state
        autoFetchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetchAndRefresh() }
        }
        refresh()
    }

    public func refresh() {
        do {
            self.counts = try Database.shared.labelCounts()
            self.unreadCounts = try Database.shared.unreadLabelCounts()
            self.mails = try Database.shared.mails(limit: 500)
            self.lastSyncedAt = Date()
        } catch {
            MailSorterLog.app.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func fetchAndRefresh() {
        guard !isFetching else { return }
        isFetching = true
        fetchError = nil
        Task {
            do {
                guard let creds = try KeychainStore.loadIMAPCredentials() else {
                    self.fetchError = "저장된 계정 정보 없음. 환경설정에서 저장하세요."
                    self.isFetching = false
                    return
                }
                let client = IMAPClient(creds: creds)
                try await client.connect()
                try await client.login()
                try await client.selectFolder("INBOX")
                let ingestor = MailIngestor(client: client, classifier: NLClassifier(), prefs: .standard)
                _ = try await ingestor.ingestUnseen()
                await client.disconnect()
            } catch {
                self.fetchError = error.localizedDescription
            }
            self.isFetching = false
            self.refresh()
        }
    }

    public var visibleMails: [Mail] {
        let filtered = filter == nil ? mails : mails.filter { $0.labels.contains(filter!) }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return filtered }
        return filtered.filter {
            $0.subject.lowercased().contains(q)
                || $0.fromAddress.lowercased().contains(q)
                || $0.body.lowercased().contains(q)
        }
    }

    public func relabel(mail: Mail, to newLabel: MailLabel) {
        relabel(mail: mail, to: Set([newLabel]))
    }

    public func relabel(mail: Mail, to newLabels: Set<MailLabel>) {
        do {
            var finalLabels = newLabels
            if finalLabels.isEmpty {
                finalLabels.insert(.normal)
            } else if finalLabels.count > 1 {
                finalLabels.remove(.normal)
            }
            try Database.shared.updateLabels(mailId: mail.id, to: finalLabels)
            EventBus.post(.labelChanged, userInfo: [
                "mailId": mail.id,
                "labels": finalLabels.map { $0.rawValue }.joined(separator: ",")
            ])
            refresh()
        } catch {
            MailSorterLog.app.error("relabel failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func toggleLabel(mail: Mail, label: MailLabel) {
        if label == .normal {
            relabel(mail: mail, to: [.normal])
            return
        }
        var newLabels = mail.labels
        if newLabels.contains(label) {
            newLabels.remove(label)
        } else {
            newLabels.insert(label)
        }
        relabel(mail: mail, to: newLabels)
    }

    public func markAsSeen(mail: Mail) {
        guard mail.seenAt == nil else { return }
        do {
            try Database.shared.updateSeen(mailId: mail.id, seenAt: Date())
            refresh()
        } catch {
            MailSorterLog.app.error("markAsSeen failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func deleteMails(ids: Set<String>) {
        let mailsToDelete = mails.filter { ids.contains($0.id) }
        guard !mailsToDelete.isEmpty else { return }
        
        Task {
            do {
                guard let creds = try KeychainStore.loadIMAPCredentials() else { return }
                let client = IMAPClient(creds: creds)
                try await client.connect()
                try await client.login()
                try await client.selectFolder("INBOX")
                
                for mail in mailsToDelete {
                    try await client.delete(uid: mail.uid)
                    try await Database.shared.pool.write { db in
                        _ = try mail.delete(db)
                    }
                }
                await client.disconnect()
                await MainActor.run {
                    self.refresh()
                }
            } catch {
                MailSorterLog.app.error("deleteMails failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func moveMails(ids: Set<String>, toFolder: String) {
        let mailsToMove = mails.filter { ids.contains($0.id) }
        guard !mailsToMove.isEmpty else { return }
        
        Task {
            do {
                guard let creds = try KeychainStore.loadIMAPCredentials() else { return }
                let client = IMAPClient(creds: creds)
                try await client.connect()
                try await client.login()
                try await client.selectFolder("INBOX")
                
                for mail in mailsToMove {
                    try await client.move(uid: mail.uid, toFolder: toFolder)
                    try await Database.shared.pool.write { db in
                        _ = try mail.delete(db)
                    }
                }
                await client.disconnect()
                await MainActor.run {
                    self.refresh()
                }
            } catch {
                MailSorterLog.app.error("moveMails failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
