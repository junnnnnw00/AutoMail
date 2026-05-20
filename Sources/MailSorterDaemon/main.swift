import Foundation
import SharedKit

let daemon = MailDaemon()

signal(SIGTERM) { _ in
    MailSorterLog.app.info("SIGTERM received, shutting down")
    exit(0)
}
signal(SIGINT) { _ in
    MailSorterLog.app.info("SIGINT received, shutting down")
    exit(0)
}

Task {
    await daemon.run()
}

RunLoop.main.run()

