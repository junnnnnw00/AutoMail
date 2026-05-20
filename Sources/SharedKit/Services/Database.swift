import Foundation
import GRDB

public final class Database: @unchecked Sendable {
    public static let shared = Database()

    public let pool: DatabasePool

    private init() {
        let url = AppPaths.databaseURL
        var config = Configuration()
        config.label = "MailSorter"
        do {
            self.pool = try DatabasePool(path: url.path, configuration: config)
            try migrator.migrate(self.pool)
        } catch {
            MailSorterLog.db.error("DB init failed: \(error.localizedDescription, privacy: .public)")
            fatalError("Could not open database at \(url.path): \(error)")
        }
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1") { db in
            try db.create(table: "mails") { t in
                t.column("id", .text).primaryKey()
                t.column("uid", .integer).notNull()
                t.column("folder", .text).notNull()
                t.column("fromAddress", .text).notNull()
                t.column("fromName", .text)
                t.column("subject", .text).notNull()
                t.column("body", .text).notNull()
                t.column("receivedAt", .datetime).notNull()
                t.column("label", .text).notNull()
                t.column("score", .double).notNull()
                t.column("userOverridden", .boolean).notNull().defaults(to: false)
                t.column("movedAt", .datetime)
                t.column("seenAt", .datetime)
            }
            try db.create(indexOn: "mails", columns: ["receivedAt"])
            try db.create(indexOn: "mails", columns: ["label"])

            try db.create(table: "feedback_queue") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("mailId", .text).notNull().references("mails", onDelete: .cascade)
                t.column("oldLabel", .text).notNull()
                t.column("newLabel", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("consumedAt", .datetime)
            }
            try db.create(indexOn: "feedback_queue", columns: ["consumedAt"])

            try db.create(table: "digest_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sentAt", .datetime).notNull()
                t.column("mailCount", .integer).notNull()
            }

            try db.create(table: "prefs") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        return m
    }

    public func reset() throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM mails")
            try db.execute(sql: "DELETE FROM feedback_queue")
            try db.execute(sql: "DELETE FROM digest_log")
        }
    }
}

public extension Database {
    func upsertMail(_ mail: Mail) throws {
        try pool.write { db in
            var finalMail = mail
            if let existing = try Mail.fetchOne(db, key: mail.id) {
                if existing.userOverridden {
                    finalMail.labels = existing.labels
                    finalMail.score = existing.score
                    finalMail.userOverridden = true
                }
                if existing.seenAt != nil {
                    finalMail.seenAt = existing.seenAt
                }
            }
            try finalMail.insert(db, onConflict: .replace)
        }
    }

    func mails(filter: MailLabel? = nil, limit: Int = 200) throws -> [Mail] {
        try pool.read { db in
            var req = Mail.order(Mail.Columns.receivedAt.desc).limit(limit)
            if let filter {
                req = Mail.filter(sql: "label LIKE ?", arguments: ["%\(filter.rawValue)%"])
                    .order(Mail.Columns.receivedAt.desc)
                    .limit(limit)
            }
            return try req.fetchAll(db)
        }
    }

    func updateLabels(mailId: String, to newLabels: Set<MailLabel>) throws {
        try pool.write { db in
            guard var mail = try Mail.fetchOne(db, key: mailId) else { return }
            let old = mail.labels
            mail.labels = newLabels
            mail.userOverridden = true
            mail.score = 1.0
            try mail.update(db)
            let fb = FeedbackEntry(mailId: mailId, oldLabel: old.primaryLabel(), newLabel: newLabels.primaryLabel())
            try fb.insert(db)
        }
    }

    func updateLabel(mailId: String, to newLabel: MailLabel) throws {
        try updateLabels(mailId: mailId, to: [newLabel])
    }

    func importantMails(since: Date) throws -> [Mail] {
        try pool.read { db in
            try Mail
                .filter(sql: "label LIKE ?", arguments: ["%\(MailLabel.important.rawValue)%"])
                .filter(Mail.Columns.receivedAt > since)
                .order(Mail.Columns.receivedAt.desc)
                .fetchAll(db)
        }
    }

    func labelCounts() throws -> [MailLabel: Int] {
        try pool.read { db in
            var out: [MailLabel: Int] = [:]
            for label in MailLabel.allCases {
                let count = try Mail.filter(sql: "label LIKE ?", arguments: ["%\(label.rawValue)%"]).fetchCount(db)
                out[label] = count
            }
            return out
        }
    }

    func unreadLabelCounts() throws -> [MailLabel: Int] {
        try pool.read { db in
            var out: [MailLabel: Int] = [:]
            for label in MailLabel.allCases {
                let count = try Mail
                    .filter(sql: "label LIKE ?", arguments: ["%\(label.rawValue)%"])
                    .filter(Mail.Columns.seenAt == nil)
                    .fetchCount(db)
                out[label] = count
            }
            return out
        }
    }

    func updateSeen(mailId: String, seenAt: Date) throws {
        try pool.write { db in
            guard var mail = try Mail.fetchOne(db, key: mailId) else { return }
            mail.seenAt = seenAt
            try mail.update(db)
        }
    }

    func unconsumedFeedback() throws -> [FeedbackEntry] {
        try pool.read { db in
            try FeedbackEntry.filter(Column("consumedAt") == nil).fetchAll(db)
        }
    }

    func markFeedbackConsumed(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try pool.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE feedback_queue SET consumedAt = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments([Date()] + ids.map { $0 as DatabaseValueConvertible })
            )
        }
    }

    func allLabeledMails() throws -> [Mail] {
        try pool.read { db in
            try Mail.fetchAll(db)
        }
    }

    func allUIDs() throws -> Set<UInt32> {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT uid FROM mails")
            let uids = rows.compactMap { $0["uid"] as UInt32? }
            return Set(uids)
        }
    }
}
