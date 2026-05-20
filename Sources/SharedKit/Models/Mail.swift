import Foundation
import GRDB

public struct Mail: Codable, Identifiable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public var id: String
    public var uid: UInt32
    public var folder: String
    public var fromAddress: String
    public var fromName: String?
    public var subject: String
    public var body: String
    public var receivedAt: Date
    public var labels: Set<MailLabel>
    public var score: Double
    public var userOverridden: Bool
    public var movedAt: Date?
    public var seenAt: Date?

    public init(
        id: String,
        uid: UInt32,
        folder: String,
        fromAddress: String,
        fromName: String? = nil,
        subject: String,
        body: String,
        receivedAt: Date,
        labels: Set<MailLabel>,
        score: Double,
        userOverridden: Bool = false,
        movedAt: Date? = nil,
        seenAt: Date? = nil
    ) {
        self.id = id
        self.uid = uid
        self.folder = folder
        self.fromAddress = fromAddress
        self.fromName = fromName
        self.subject = subject
        self.body = body
        self.receivedAt = receivedAt
        self.labels = labels
        self.score = score
        self.userOverridden = userOverridden
        self.movedAt = movedAt
        self.seenAt = seenAt
    }

    public static let databaseTableName = "mails"

    public enum CodingKeys: String, CodingKey {
        case id
        case uid
        case folder
        case fromAddress
        case fromName
        case subject
        case body
        case receivedAt
        case labels = "label"
        case score
        case userOverridden
        case movedAt
        case seenAt
    }

    public enum Columns {
        public static let id = Column("id")
        public static let uid = Column("uid")
        public static let folder = Column("folder")
        public static let fromAddress = Column("fromAddress")
        public static let fromName = Column("fromName")
        public static let subject = Column("subject")
        public static let body = Column("body")
        public static let receivedAt = Column("receivedAt")
        public static let label = Column("label")
        public static let score = Column("score")
        public static let userOverridden = Column("userOverridden")
        public static let movedAt = Column("movedAt")
        public static let seenAt = Column("seenAt")
    }
}

public struct FeedbackEntry: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: Int64?
    public var mailId: String
    public var oldLabel: MailLabel
    public var newLabel: MailLabel
    public var createdAt: Date
    public var consumedAt: Date?

    public init(id: Int64? = nil, mailId: String, oldLabel: MailLabel, newLabel: MailLabel, createdAt: Date = Date(), consumedAt: Date? = nil) {
        self.id = id
        self.mailId = mailId
        self.oldLabel = oldLabel
        self.newLabel = newLabel
        self.createdAt = createdAt
        self.consumedAt = consumedAt
    }

    public static let databaseTableName = "feedback_queue"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct DigestRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: Int64?
    public var sentAt: Date
    public var mailCount: Int

    public init(id: Int64? = nil, sentAt: Date = Date(), mailCount: Int) {
        self.id = id
        self.sentAt = sentAt
        self.mailCount = mailCount
    }

    public static let databaseTableName = "digest_log"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Set: @retroactive SQLExpressible where Element == MailLabel {}
extension Set: @retroactive StatementBinding where Element == MailLabel {}
extension Set: @retroactive DatabaseValueConvertible where Element == MailLabel {
    public var databaseValue: DatabaseValue {
        let stringArray = self.map { $0.rawValue }
        if let data = try? JSONEncoder().encode(stringArray),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString.databaseValue
        }
        return "".databaseValue
    }
    
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Set<MailLabel>? {
        guard let string = String.fromDatabaseValue(dbValue) else { return nil }
        if let data = string.data(using: .utf8),
           let stringArray = try? JSONDecoder().decode([String].self, from: data) {
            return Set(stringArray.compactMap { MailLabel(rawValue: $0) })
        }
        let components = string.split(separator: ",").map(String.init)
        let labels = components.compactMap { MailLabel(rawValue: $0) }
        return labels.isEmpty ? nil : Set(labels)
    }
}
