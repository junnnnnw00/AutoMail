import Foundation

public actor MailIngestor {
    private let client: IMAPClientProtocol
    private let classifier: NLClassifier
    private let prefs: Prefs

    public init(client: IMAPClientProtocol, classifier: NLClassifier, prefs: Prefs = .standard) {
        self.client = client
        self.classifier = classifier
        self.prefs = prefs
    }

    private static func notificationContent(for mails: [Mail]) -> (title: String, body: String) {
        if mails.count == 1 {
            let m = mails[0]
            let preview = m.body.replacingOccurrences(of: "\n", with: " ").prefix(80)
            return (m.subject, (m.fromName ?? m.fromAddress) + "\n" + String(preview))
        }
        let bullets = mails.prefix(3).map { "• \($0.subject)" }.joined(separator: "\n")
        return ("중요 메일 \(mails.count)건", bullets)
    }

    public func ingestUnseen() async throws -> Int {
        let knownUIDs = (try? Database.shared.allUIDs()) ?? []
        let messages = try await client.fetchUnseen(excluding: knownUIDs)
        var newlyImportant: [Mail] = []
        for msg in messages {
            let cleanBody = msg.body.replacingOccurrences(of: #"data:image/[^;]+;base64,[a-zA-Z0-9+/=]+"#, with: "[IMAGE]", options: .regularExpression)
            let classificationText = String(cleanBody.prefix(10000))
            let result = classifier.classify(subject: msg.subject, body: classificationText, fromAddress: msg.from)
            let mail = Mail(
                id: msg.messageId,
                uid: msg.uid,
                folder: "INBOX",
                fromAddress: msg.from,
                fromName: msg.fromName,
                subject: msg.subject,
                body: msg.body,
                receivedAt: msg.date,
                labels: result.labels,
                score: result.score,
                userOverridden: false,
                classificationSource: result.source.description
            )
            try Database.shared.upsertMail(mail)
            let labelsString = mail.labels.map { $0.rawValue }.joined(separator: ",")
            MailSorterLog.ingest.info("classified uid=\(msg.uid) [\(labelsString, privacy: .public)] score=\(result.score, privacy: .public)")
            if let target = prefs.folder(for: mail.labels) {
                do {
                    try await client.move(uid: msg.uid, toFolder: target)
                    var moved = mail
                    moved.folder = target
                    moved.movedAt = Date()
                    try Database.shared.upsertMail(moved)
                } catch {
                    MailSorterLog.ingest.error("move failed uid=\(msg.uid): \(error.localizedDescription, privacy: .public)")
                }
            }
            if mail.labels.contains(.important) {
                newlyImportant.append(mail)
            }
        }
        if !messages.isEmpty {
            EventBus.post(.newMail, userInfo: ["count": String(messages.count)])
        }
        if !newlyImportant.isEmpty && prefs.immediateImportantAlerts {
            // 데몬은 번들 없어 UNUserNotificationCenter 직접 사용 불가 → 앱에 릴레이
            let (title, body) = Self.notificationContent(for: newlyImportant)
            EventBus.post(.showNotification, userInfo: ["title": title, "body": body])
        }
        return messages.count
    }
}
