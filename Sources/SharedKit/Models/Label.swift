import Foundation

public enum MailLabel: String, Codable, CaseIterable, Sendable {
    case important
    case normal
    case newsletter
    case ad

    public var displayName: String {
        switch self {
        case .important: return "중요"
        case .normal: return "일반"
        case .newsletter: return "교내회보"
        case .ad: return "광고"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .important: return "star.fill"
        case .normal: return "envelope"
        case .newsletter: return "newspaper"
        case .ad: return "tag"
        }
    }

    public var defaultIMAPFolder: String? {
        switch self {
        case .important, .normal: return nil
        case .newsletter: return "교내회보"
        case .ad: return "광고"
        }
    }
}

public extension Collection where Element == MailLabel {
    func primaryLabel() -> MailLabel {
        if contains(.important) { return .important }
        if contains(.newsletter) { return .newsletter }
        if contains(.ad) { return .ad }
        return .normal
    }
}
