import Testing
@testable import SharedKit

@Suite("MailLabel")
struct MailLabelTests {
    @Test func allCasesHaveDisplayName() {
        for label in MailLabel.allCases {
            #expect(!label.displayName.isEmpty)
            #expect(!label.sfSymbol.isEmpty)
        }
    }

    @Test func folderMappingForNonImportant() {
        #expect(MailLabel.important.defaultIMAPFolder == nil)
        #expect(MailLabel.normal.defaultIMAPFolder == nil)
        #expect(MailLabel.newsletter.defaultIMAPFolder == "교내회보")
        #expect(MailLabel.ad.defaultIMAPFolder == "광고")
    }
}
