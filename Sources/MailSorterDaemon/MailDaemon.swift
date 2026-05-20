import Foundation
import SharedKit

public actor MailDaemon {
    private var client: IMAPClient?
    private var ingestor: MailIngestor?
    private var classifier: NLClassifier?
    private let digestScheduler = DigestScheduler()
    private let retrainScheduler = RetrainScheduler()
    private let prefs = Prefs.standard
    private var labelChangeObserver: NSObjectProtocol?

    public init() {}

    public func run() async {
        MailSorterLog.app.info("daemon starting")
        await digestScheduler.start()
        await retrainScheduler.start()

        Task {
            while !Task.isCancelled {
                EventBus.post(.daemonHeartbeat)
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            }
        }

        labelChangeObserver = EventBus.observe(.labelChanged) { [weak self] note in
            let info = (note.userInfo as? [String: String]) ?? [:]
            Task { [weak self] in
                await self?.handleLabelChange(info: info)
            }
        }

        var backoff: UInt64 = 1
        while !Task.isCancelled {
            do {
                try await connectAndRun()
                backoff = 1
            } catch {
                MailSorterLog.imap.error("session ended: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(backoff * 2, 60)
            }
        }
    }

    private func connectAndRun() async throws {
        guard let creds = try KeychainStore.loadIMAPCredentials() else {
            MailSorterLog.imap.notice("no credentials, waiting 30s")
            try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            return
        }

        let classifier = NLClassifier()
        self.classifier = classifier

        let client = IMAPClient(creds: creds)
        self.client = client
        try await client.connect()
        try await client.login()

        try await ensureFolders(client: client)
        try await client.selectFolder("INBOX")

        let ingestor = MailIngestor(client: client, classifier: classifier, prefs: prefs)
        self.ingestor = ingestor

        _ = try await ingestor.ingestUnseen()
        await retrainScheduler.triggerIfNeeded()

        while !Task.isCancelled {
            try await client.idle()
            _ = try await ingestor.ingestUnseen()
            await retrainScheduler.triggerIfNeeded()
        }
    }

    private func onIdleChange() async {
        guard let ingestor else { return }
        do {
            _ = try await ingestor.ingestUnseen()
            await retrainScheduler.triggerIfNeeded()
        } catch {
            MailSorterLog.ingest.error("ingest on idle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureFolders(client: IMAPClient) async throws {
        let existing = (try? await client.listFolders()) ?? []
        for folder in [prefs.folderForNewsletter, prefs.folderForAd] {
            if !existing.contains(folder) {
                try await client.createFolder(folder)
            }
        }
    }

    private func handleLabelChange(info: [String: String]) async {
        guard let mailId = info["mailId"] else { return }

        let labels: Set<MailLabel>
        if let labelsRaw = info["labels"] {
            labels = Set(labelsRaw.split(separator: ",").map(String.init).compactMap { MailLabel(rawValue: $0) })
        } else if let labelRaw = info["label"], let singleLabel = MailLabel(rawValue: labelRaw) {
            labels = [singleLabel]
        } else {
            return
        }

        if let target = prefs.folder(for: labels) {
            guard let client else { return }
            if let mail = try? await Database.shared.pool.read({ db in
                try Mail.fetchOne(db, key: mailId)
            }), mail.folder != target {
                do {
                    try await client.move(uid: mail.uid, toFolder: target)
                    var moved = mail
                    moved.folder = target
                    moved.movedAt = Date()
                    try Database.shared.upsertMail(moved)
                } catch {
                    MailSorterLog.ingest.error("Daemon move on label change failed uid=\(mail.uid): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        await retrainScheduler.triggerIfNeeded()
    }
}
