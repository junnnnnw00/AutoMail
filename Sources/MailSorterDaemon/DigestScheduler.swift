import Foundation
import SharedKit

public actor DigestScheduler {
    private let prefs: Prefs
    private var task: Task<Void, Never>?

    public init(prefs: Prefs = .standard) {
        self.prefs = prefs
    }

    public func start() {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                let now = Date()
                let next = nextDigestTime(from: now)
                let wait = next.timeIntervalSince(now)
                MailSorterLog.app.info("Next digest in \(wait/60, privacy: .public) mins")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { break }
                await sendDigest()
            }
        }
    }

    private func nextDigestTime(from date: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = .current
        let hour = prefs.digestHour
        let min = prefs.digestMinute
        let target = cal.date(bySettingHour: hour, minute: min, second: 0, of: date)!
        if target <= date {
            return cal.date(byAdding: .day, value: 1, to: target)!
        }
        return target
    }

    private func sendDigest() async {
        let since = Date().addingTimeInterval(-24 * 3600)
        let mails: [Mail]
        do {
            mails = try Database.shared.importantMails(since: since)
        } catch {
            MailSorterLog.app.error("digest fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if mails.isEmpty {
            MailSorterLog.app.info("no important mail for digest, skipping")
            return
        }
        
        var body = "어제 이후 중요 메일 \(mails.count)건이 수신되었습니다.\n\n"
        for m in mails.prefix(5) {
            body += "• \(m.subject)\n"
        }
        if mails.count > 5 {
            body += "... 외 \(mails.count - 5)건"
        }

        EventBus.post(.showNotification, userInfo: ["title": "오늘의 메일 다이제스트", "body": body])

        do {
            let mailCount = mails.count
            try await Database.shared.pool.write { db in
                try DigestRecord(mailCount: mailCount).insert(db)
            }
            MailSorterLog.app.info("sent daily digest for \(mails.count, privacy: .public) mails")
        } catch {
            MailSorterLog.app.error("digest write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
