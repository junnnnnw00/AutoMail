import Foundation

public enum MailSorterEvent: String, Sendable {
    case newMail = "com.junwoo.mailsorter.newMail"
    case modelReloaded = "com.junwoo.mailsorter.modelReloaded"
    case labelChanged = "com.junwoo.mailsorter.labelChanged"
    case daemonHeartbeat = "com.junwoo.mailsorter.daemonHeartbeat"
    // 데몬→앱 알림 릴레이 (데몬은 번들 없어 UNUserNotificationCenter 사용 불가)
    case showNotification = "com.junwoo.mailsorter.showNotification"
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
