import Foundation
import GRDB

public struct ClassifierStats: Sendable {
    public var totalMails: Int
    public var userOverrideCount: Int
    public var labelCounts: [MailLabel: Int]
    public var sourceCounts: [String: Int]
    public var pendingFeedback: Int
    public var lastTrainedAt: Date?
    public var modelExists: Bool

    public var autoAccuracyRate: Double {
        totalMails > 0 ? 1.0 - Double(userOverrideCount) / Double(totalMails) : 1.0
    }
}

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

        m.registerMigration("v2") { db in
            try db.execute(sql: "UPDATE mails SET label = '[\"' || label || '\"]' WHERE label NOT LIKE '[%';")
        }

        m.registerMigration("v3") { db in
            try db.alter(table: "mails") { t in
                t.add(column: "classificationSource", .text)
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

    func mails(filter: MailLabel? = nil, searchQuery: String? = nil, limit: Int = 200) throws -> [Mail] {
        try pool.read { db in
            var req = Mail.all()
            if let filter {
                req = req.filter(sql: "label LIKE ?", arguments: ["%\(filter.rawValue)%"])
            }
            if let searchQuery, !searchQuery.isEmpty {
                let likeArg = "%\(searchQuery)%"
                req = req.filter(sql: "subject LIKE ? OR fromAddress LIKE ? OR substr(body,1,2000) LIKE ?",
                                 arguments: [likeArg, likeArg, likeArg])
            }
            return try req.order(Mail.Columns.receivedAt.desc).limit(limit).fetchAll(db)
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
            // 같은 라벨로의 변경은 피드백 불필요
            guard old.primaryLabel() != newLabels.primaryLabel() else { return }
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

    func classifierStats() throws -> ClassifierStats {
        try pool.read { db in
            let total = try Mail.fetchCount(db)
            let overridden = try Mail.filter(Column("userOverridden") == true).fetchCount(db)

            var labelCounts: [MailLabel: Int] = [:]
            for label in MailLabel.allCases {
                labelCounts[label] = try Mail
                    .filter(sql: "label LIKE ?", arguments: ["%\(label.rawValue)%"])
                    .fetchCount(db)
            }

            var sourceCounts: [String: Int] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    CASE
                        WHEN classificationSource LIKE 'model%'    THEN 'model'
                        WHEN classificationSource LIKE 'combined%' THEN 'combined'
                        WHEN classificationSource LIKE 'rule%'     THEN 'rule'
                        WHEN classificationSource LIKE 'fallback%' THEN 'fallback'
                        ELSE 'unknown'
                    END as src,
                    COUNT(*) as cnt
                FROM mails
                GROUP BY src
                """)
            for row in rows {
                if let src = row["src"] as String?, let cnt = row["cnt"] as Int? {
                    sourceCounts[src] = cnt
                }
            }

            let pending = try FeedbackEntry.filter(Column("consumedAt") == nil).fetchCount(db)
            return ClassifierStats(
                totalMails: total,
                userOverrideCount: overridden,
                labelCounts: labelCounts,
                sourceCounts: sourceCounts,
                pendingFeedback: pending,
                lastTrainedAt: Prefs.standard.lastTrainedAt,
                modelExists: FileManager.default.fileExists(atPath: AppPaths.compiledClassifierURL.path)
            )
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
