import Foundation

public enum MailSorterEvent: String, Sendable {
    case newMail = "com.junwoo.mailsorter.newMail"
    case modelReloaded = "com.junwoo.mailsorter.modelReloaded"
    case labelChanged = "com.junwoo.mailsorter.labelChanged"
    case daemonHeartbeat = "com.junwoo.mailsorter.daemonHeartbeat"
}

public enum EventBus {
    public static func post(_ event: MailSorterEvent, userInfo: [String: String]? = nil) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(event.rawValue),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    public static func observe(_ event: MailSorterEvent, queue: OperationQueue? = .main, handler: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(event.rawValue),
            object: nil,
            queue: queue,
            using: handler
        )
    }
}
