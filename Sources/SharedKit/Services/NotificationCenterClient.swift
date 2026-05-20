import Foundation
import UserNotifications

public final class NotificationCenterClient: @unchecked Sendable {
    public static let shared = NotificationCenterClient()

    private init() {}

    public func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            MailSorterLog.notify.info("authorization granted=\(granted)")
        } catch {
            MailSorterLog.notify.error("auth failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func notifyImportant(mails: [Mail]) async {
        guard !mails.isEmpty else { return }
        let content = UNMutableNotificationContent()
        if mails.count == 1 {
            let m = mails[0]
            content.title = m.subject
            let shortBody = m.body.replacingOccurrences(of: "\n", with: " ").prefix(80)
            content.body = (m.fromName ?? m.fromAddress) + "\n" + String(shortBody)
        } else {
            content.title = "중요 메일 \(mails.count)건"
            content.body = mails.prefix(3).map { "• \($0.subject)" }.joined(separator: "\n")
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "important.\(UUID().uuidString)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            MailSorterLog.notify.error("notify failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func scheduleDailyDigest(body: String) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "오늘의 메일 다이제스트"
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "daily.digest.\(UUID().uuidString)", content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            MailSorterLog.notify.error("digest notify failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
