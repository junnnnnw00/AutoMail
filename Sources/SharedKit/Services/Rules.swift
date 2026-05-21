import Foundation

public struct RuleHit: Sendable {
    public let label: MailLabel
    public let score: Double
    public let reason: String
}

public struct Rules: Sendable {
    public struct Pattern: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var regex: String
        public var label: String
        public var score: Double

        public init(id: UUID = UUID(), regex: String, label: String, score: Double) {
            self.id = id
            self.regex = regex
            self.label = label
            self.score = score
        }

        enum CodingKeys: String, CodingKey { case id, regex, label, score }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id    = (try? c.decode(UUID.self,   forKey: .id))    ?? UUID()
            self.regex = try  c.decode(String.self,  forKey: .regex)
            self.label = try  c.decode(String.self,  forKey: .label)
            self.score = try  c.decode(Double.self,  forKey: .score)
        }
    }

    private let customPatterns: [Pattern]?

    public var patterns: [Pattern] {
        customPatterns ?? Prefs.standard.rulesPatterns
    }

    public static let defaultPatterns: [Pattern] = [
        .init(regex: #"^\s*\[?\s*교내회보\s*\]?"#, label: "newsletter", score: 0.98),
        .init(regex: #"^\s*\[?\s*학사공지\s*\]?"#, label: "newsletter", score: 0.92),
        .init(regex: #"(?i)\bnewsletter\b"#, label: "newsletter", score: 0.85),
        .init(regex: #"(?i)\bunsubscribe\b"#, label: "ad", score: 0.85),
        .init(regex: #"광고|마케팅|특가|이벤트|프로모션|sale|할인쿠폰"#, label: "ad", score: 0.9),
        .init(regex: #"장학금|장학|학자금|등록금"#, label: "important", score: 0.85),
        .init(regex: #"성적|학점|졸업|수강신청|기말|중간고사"#, label: "important", score: 0.9)
    ]

    public init(patterns: [Pattern]? = nil) {
        self.customPatterns = patterns
    }

    public func evaluate(subject: String, body: String, fromAddress: String) -> [RuleHit] {
        let isSchoolMail = fromAddress.lowercased() == "postech.ac.kr" ||
                           fromAddress.lowercased().hasSuffix("@postech.ac.kr") ||
                           fromAddress.lowercased().hasSuffix(".postech.ac.kr")
        
        let haystack = subject + "\n" + body + "\n" + fromAddress
        var hits: [RuleHit] = []
        for pattern in patterns {
            if isSchoolMail && pattern.label == MailLabel.ad.rawValue {
                continue
            }
            
            guard let regex = try? NSRegularExpression(pattern: pattern.regex, options: []) else { continue }
            let range = NSRange(haystack.startIndex..., in: haystack)
            if regex.firstMatch(in: haystack, options: [], range: range) != nil {
                if let label = MailLabel(rawValue: pattern.label) {
                    hits.append(RuleHit(label: label, score: pattern.score, reason: pattern.regex))
                }
            }
        }
        return hits
    }
}
