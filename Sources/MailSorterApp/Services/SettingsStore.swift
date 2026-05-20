import Foundation
import SwiftUI
import SharedKit

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var imapHost: String
    @Published public var imapPort: Int
    @Published public var imapUseTLS: Bool
    @Published public var imapUsername: String
    @Published public var imapPassword: String

    @Published public var digestTime: Date
    @Published public var immediateImportantAlerts: Bool
    @Published public var folderNewsletter: String
    @Published public var folderAd: String
    @Published public var retrainThreshold: Int

    private let prefs = Prefs.standard

    public init() {
        let existing = (try? KeychainStore.loadIMAPCredentials())
        self.imapHost = existing?.host ?? "imap.gmail.com"
        self.imapPort = existing?.port ?? 993
        self.imapUseTLS = existing?.useTLS ?? true
        self.imapUsername = existing?.username ?? ""
        self.imapPassword = existing?.password ?? ""

        var components = DateComponents()
        components.hour = prefs.digestHour
        components.minute = prefs.digestMinute
        self.digestTime = Calendar.current.date(from: components) ?? Date()
        self.immediateImportantAlerts = prefs.immediateImportantAlerts
        self.folderNewsletter = prefs.folderForNewsletter
        self.folderAd = prefs.folderForAd
        self.retrainThreshold = prefs.retrainThreshold
    }

    public func saveCredentials() throws {
        let creds = IMAPCredentials(
            host: imapHost,
            port: imapPort,
            useTLS: imapUseTLS,
            username: imapUsername,
            password: imapPassword
        )
        try KeychainStore.saveIMAPCredentials(creds)
    }

    public func savePrefs() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: digestTime)
        prefs.digestHour = components.hour ?? 8
        prefs.digestMinute = components.minute ?? 0
        prefs.immediateImportantAlerts = immediateImportantAlerts
        prefs.folderForNewsletter = folderNewsletter
        prefs.folderForAd = folderAd
        prefs.retrainThreshold = retrainThreshold
    }
}
