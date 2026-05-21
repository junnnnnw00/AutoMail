import Testing
@testable import SharedKit

@Suite("Rules")
struct RulesTests {
    @Test func newsletterPrefix() {
        let rules = Rules(patterns: Rules.defaultPatterns)
        let hits = rules.evaluate(subject: "[교내회보] 5월 학사 안내", body: "", fromAddress: "news@school.ac.kr")
        let newsletterHit = hits.first(where: { $0.label == .newsletter })
        #expect(newsletterHit != nil)
        #expect((newsletterHit?.score ?? 0) > 0.9)
    }

    @Test func unsubscribeAd() {
        let rules = Rules(patterns: Rules.defaultPatterns)
        let hits = rules.evaluate(subject: "Spring Sale!", body: "Click unsubscribe at the bottom", fromAddress: "promo@brand.com")
        #expect(hits.contains(where: { $0.label == .ad }))
    }

    @Test func importantScholarship() {
        let rules = Rules(patterns: Rules.defaultPatterns)
        let hits = rules.evaluate(subject: "장학금 신청 안내", body: "마감 임박", fromAddress: "scholarship@school.ac.kr")
        #expect(hits.contains(where: { $0.label == .important }))
    }

    @Test func unmatched() {
        let rules = Rules(patterns: Rules.defaultPatterns)
        let hits = rules.evaluate(subject: "Lunch tomorrow?", body: "Hey, want to grab lunch?", fromAddress: "friend@example.com")
        #expect(hits.isEmpty)
    }

    @Test func multipleMatchingRules() {
        let rules = Rules(patterns: Rules.defaultPatterns)
        let hits = rules.evaluate(subject: "[교내회보] 2026학년도 1학기 국가장학금 신청 안내", body: "", fromAddress: "scholarship@school.ac.kr")
        let labels = Set(hits.map { $0.label })
        #expect(labels.contains(.newsletter))
        #expect(labels.contains(.important))
    }

    @Test func schoolDomainAdExclusion() {
        let rules = Rules(patterns: Rules.defaultPatterns)
        // A school mail containing "이벤트" (event) which would normally trigger an "ad" rule hit
        let hits = rules.evaluate(
            subject: "[교내회보] 대학 창업 캠프 이벤트 안내",
            body: "많은 참여 바랍니다.",
            fromAddress: "startup@postech.ac.kr"
        )
        // Check that 'ad' is excluded because the sender is from postech.ac.kr
        #expect(!hits.contains(where: { $0.label == .ad }))
        #expect(hits.contains(where: { $0.label == .newsletter }))
    }

    @Test func classifierSchoolDomainAdFiltering() {
        let classifier = NLClassifier()
        let result = classifier.classify(
            subject: "[교내회보] 대학 창업 캠프 이벤트 안내",
            body: "Click unsubscribe to stop mailings.",
            fromAddress: "startup@postech.ac.kr"
        )
        #expect(!result.labels.contains(.ad))
        #expect(result.labels.contains(.newsletter))
    }
}
