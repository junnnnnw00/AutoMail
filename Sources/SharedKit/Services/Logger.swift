import Foundation
import OSLog

public enum MailSorterLog {
    public static let subsystem = "com.junwoo.mailsorter"

    public static let imap = Logger(subsystem: subsystem, category: "imap")
    public static let ingest = Logger(subsystem: subsystem, category: "ingest")
    public static let classifier = Logger(subsystem: subsystem, category: "classifier")
    public static let trainer = Logger(subsystem: subsystem, category: "trainer")
    public static let notify = Logger(subsystem: subsystem, category: "notify")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let db = Logger(subsystem: subsystem, category: "db")
}
