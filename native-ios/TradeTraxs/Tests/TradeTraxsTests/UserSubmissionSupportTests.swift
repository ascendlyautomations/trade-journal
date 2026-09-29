import Testing
@testable import TradeTraxs

struct UserSubmissionSupportTests {
    @Test func storagePathMatchesWebConvention() {
        let path = SubmissionScreenshotUpload.storageObjectPath(
            userID: "user-abc",
            prefix: "support"
        )
        #expect(path.hasPrefix("support/user-abc/opt/"))
        #expect(path.hasSuffix(".jpg"))
    }

    @Test func bugMetadataPageURL() {
        #expect(SubmissionDeviceMetadata.bugReportPageURL == "ios://settings/support/bug-report")
    }

    @Test func deviceMetadataIsNonEmpty() {
        let value = SubmissionDeviceMetadata.compactEnvironmentString()
        #expect(!value.isEmpty)
        #expect(value.contains("TradeTraxs"))
    }

    @Test func supportTopicsMapToExistingTicketCategories() {
        #expect(SupportContactTopic.account.ticketCategory == .account)
        #expect(SupportContactTopic.brokerIntegration.ticketCategory == .broker_integration)
        #expect(SupportContactTopic.bugTechnical.ticketCategory == .bug)
        #expect(SupportContactTopic.billing.ticketCategory == .billing)
        #expect(SupportContactTopic.other.ticketCategory == .general)
        #expect(!SupportContactTopic.account.ticketSubject.isEmpty)
    }

    @Test func productFeedbackSubjectIncludesTypeAndOptionalTitle() {
        let type = ProductFeedbackType.featureRequest
        #expect(type.composedSubject(optionalTitle: "") == "Feature Request")
        #expect(type.composedSubject(optionalTitle: "Dark charts") == "Feature Request: Dark charts")
    }

    @Test func productFeedbackSubjectCodecParsesAllNativeTypes() {
        #expect(ProductFeedbackSubjectCodec.parse("Feature Request").type == .featureRequest)
        #expect(ProductFeedbackSubjectCodec.parse("Feature Request: Widgets").title == "Widgets")
        #expect(ProductFeedbackSubjectCodec.parse("Improvement").type == .improvement)
        #expect(ProductFeedbackSubjectCodec.parse("Bug: Crash on launch").type == .bug)
        #expect(ProductFeedbackSubjectCodec.parse("Other").type == .other)
        #expect(ProductFeedbackSubjectCodec.parse("Random web subject").type == nil)
    }
}
