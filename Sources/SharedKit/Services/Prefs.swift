import Foundation

public struct Prefs: @unchecked Sendable {
    public static let standard = Prefs()
    private let defaults: UserDefaults = UserDefaults(suiteName: "com.junwoo.mailsorter.shared") ?? .standard

    public init() {}

    private enum Key {
        static let digestHour = "digest.hour"
        static let digestMinute = "digest.minute"
        static let immediateImportant = "notify.immediateImportant"
        static let folderMapNewsletter = "folder.newsletter"
        static let folderMapAd = "folder.ad"
        static let lastTrainedAt = "trainer.lastRunAt"
        static let retrainThreshold = "trainer.threshold"
        static let onboardingComplete = "onboarding.complete"
        static let rulesPatterns = "rules.patterns"
    }

    public var digestHour: Int {
        get { defaults.object(forKey: Key.digestHour) as? Int ?? 8 }
        nonmutating set { defaults.set(newValue, forKey: Key.digestHour) }
    }

    public var digestMinute: Int {
        get { defaults.object(forKey: Key.digestMinute) as? Int ?? 0 }
        nonmutating set { defaults.set(newValue, forKey: Key.digestMinute) }
    }

    public var immediateImportantAlerts: Bool {
        get { defaults.object(forKey: Key.immediateImportant) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.immediateImportant) }
    }

    public var folderForNewsletter: String {
        get { defaults.string(forKey: Key.folderMapNewsletter) ?? "교내회보" }
        nonmutating set { defaults.set(newValue, forKey: Key.folderMapNewsletter) }
    }

    public var folderForAd: String {
        get { defaults.string(forKey: Key.folderMapAd) ?? "광고" }
        nonmutating set { defaults.set(newValue, forKey: Key.folderMapAd) }
    }

    public var lastTrainedAt: Date? {
        get { defaults.object(forKey: Key.lastTrainedAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.lastTrainedAt) }
    }

    public var retrainThreshold: Int {
        get { defaults.object(forKey: Key.retrainThreshold) as? Int ?? 20 }
        nonmutating set { defaults.set(newValue, forKey: Key.retrainThreshold) }
    }

    public var onboardingComplete: Bool {
        get { defaults.bool(forKey: Key.onboardingComplete) }
        nonmutating set { defaults.set(newValue, forKey: Key.onboardingComplete) }
    }

    public var rulesPatterns: [Rules.Pattern] {
        get {
            guard let data = defaults.data(forKey: Key.rulesPatterns),
                  let patterns = try? JSONDecoder().decode([Rules.Pattern].self, from: data) else {
                return Rules.defaultPatterns
            }
            return patterns
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.rulesPatterns)
            }
        }
    }

    public func folder(for label: MailLabel) -> String? {
        switch label {
        case .important, .normal: return nil
        case .newsletter: return folderForNewsletter
        case .ad: return folderForAd
        }
    }

    public func folder(for labels: Set<MailLabel>) -> String? {
        if labels.contains(.ad) {
            return folderForAd
        }
        if labels.contains(.newsletter) {
            return folderForNewsletter
        }
        return nil
    }
}
