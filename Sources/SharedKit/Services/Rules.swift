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
        // important: 개인 대상 액션 항목만 — 공지형 패턴 제외 (ML이 학습)
        .init(regex: #"장학생\s*(?:선발|선정|확정|합격|지급대상)|장학금\s*지급\s*(?:안내|대상자)"#, label: "important", score: 0.95),
        .init(regex: #"성적\s*이의신청|학점\s*정정\s*기간|졸업\s*(?:심사|판정|인정|예비심사)"#, label: "important", score: 0.92),
    ]

    public init(patterns: [Pattern]? = nil) {
        self.customPatterns = patterns
    }

    public func evaluate(subject: String, body: String, fromAddress: String) -> [RuleHit] {
        let isSchoolMail = fromAddress.lowercased() == "postech.ac.kr" ||
                           fromAddress.lowercased().hasSuffix("@postech.ac.kr") ||
                           fromAddress.lowercased().hasSuffix(".postech.ac.kr")
        let isNewsletterSubject = Rules.isNewsletterPrefix(subject)

        let haystack = subject + "\n" + body + "\n" + fromAddress
        var hits: [RuleHit] = []
        for pattern in patterns {
            if isSchoolMail && pattern.label == MailLabel.ad.rawValue { continue }
            // 교내회보/학사공지 제목 → important 규칙 스킵 (ML에 위임)
            if isNewsletterSubject && pattern.label == MailLabel.important.rawValue { continue }

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

    public static func isNewsletterPrefix(_ subject: String) -> Bool {
        let pattern = #"^\s*\[?\s*(?:교내회보|학사공지|Today's POSTECH|TODAY)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil
    }
}
