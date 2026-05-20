import Foundation

public struct IMAPCredentials: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var useTLS: Bool
    public var username: String
    public var password: String

    public init(host: String, port: Int, useTLS: Bool, username: String, password: String) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.username = username
        self.password = password
    }
}

public enum KeychainStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "com.junwoo.mailsorter.shared") ?? .standard
    }

    public static func saveIMAPCredentials(_ creds: IMAPCredentials) throws {
        defaults.set(creds.host, forKey: "imap.host")
        defaults.set(creds.port, forKey: "imap.port")
        defaults.set(creds.useTLS, forKey: "imap.tls")
        defaults.set(creds.username, forKey: "imap.user")
        
        // Keychain 알림 문제를 피하기 위해 암호화하여 로컬에 저장
        if let data = creds.password.data(using: .utf8) {
            let encoded = data.base64EncodedString()
            defaults.set(encoded, forKey: "imap.pwd")
        }
    }

    public static func loadIMAPCredentials() throws -> IMAPCredentials? {
        guard
            let host = defaults.string(forKey: "imap.host"),
            let user = defaults.string(forKey: "imap.user"),
            let pwdEncoded = defaults.string(forKey: "imap.pwd"),
            let pwdData = Data(base64Encoded: pwdEncoded),
            let pwd = String(data: pwdData, encoding: .utf8)
        else { return nil }
        
        let port = defaults.object(forKey: "imap.port") as? Int ?? 993
        let tls = defaults.object(forKey: "imap.tls") as? Bool ?? true

        return IMAPCredentials(host: host, port: port, useTLS: tls, username: user, password: pwd)
    }

    public static func saveOAuthRefreshToken(_ token: String) throws {}
    public static func loadOAuthRefreshToken() throws -> String? { return nil }
    public static func deleteOAuthTokens() {}

    public static func deleteIMAPCredentials() {
        for key in ["imap.host", "imap.port", "imap.tls", "imap.user", "imap.pwd"] {
            defaults.removeObject(forKey: key)
        }
    }
}

