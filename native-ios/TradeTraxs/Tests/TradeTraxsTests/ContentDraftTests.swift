import XCTest
@testable import TradeTraxs

final class ContentDraftTests: XCTestCase {
    func testEmptyTradeIgnoresAccountAndDefaultSide() {
        var state = TradeComposerDraftState()
        state.accountID = "account-1"
        state.side = TradeSide.long.rawValue
        state.entryAt = ContentDraftDateCodec.string(from: Date())
        XCTAssertTrue(state.isMeaningfullyEmpty)

        state.symbol = " mnq "
        XCTAssertFalse(state.isMeaningfullyEmpty)
    }

    func testEmptyPostAchievementAndStory() {
        XCTAssertTrue(PostComposerDraftState().isMeaningfullyEmpty)
        XCTAssertFalse(PostComposerDraftState(body: "Had a great trading day").isMeaningfullyEmpty)

        XCTAssertTrue(AchievementComposerDraftState().isMeaningfullyEmpty)
        var achievement = AchievementComposerDraftState()
        achievement.title = "Payout"
        XCTAssertFalse(achievement.isMeaningfullyEmpty)

        XCTAssertTrue(StoryComposerDraftState().isMeaningfullyEmpty)
        var story = StoryComposerDraftState()
        story.textOverlays = [
            StoryTextOverlayRecord(
                id: UUID(),
                text: "Morning session",
                x: 0.5,
                y: 0.5,
                scale: 1,
                rotation: 0,
                red: 1,
                green: 1,
                blue: 1,
                alpha: 1,
                alignment: "center",
                background: false
            )
        ]
        XCTAssertFalse(story.isMeaningfullyEmpty)
    }

    func testPreviewTitles() {
        var trade = ContentDraftPayload()
        trade.trade = TradeComposerDraftState(symbol: "MNQ")
        XCTAssertEqual(ContentDraftPreview.title(type: .trade, payload: trade), "Trade • MNQ")

        var post = ContentDraftPayload()
        post.post = PostComposerDraftState(body: "Had a great trading day and stayed patient")
        XCTAssertEqual(
            ContentDraftPreview.title(type: .post, payload: post),
            "Post • \"Had a great trading day and stayed patient\""
        )

        var achievement = ContentDraftPayload()
        achievement.achievement = AchievementComposerDraftState(title: "Payout")
        XCTAssertEqual(
            ContentDraftPreview.title(type: .achievement, payload: achievement),
            "Achievement • Payout"
        )

        var story = ContentDraftPayload()
        story.story = StoryComposerDraftState(
            textOverlays: [
                StoryTextOverlayRecord(
                    id: UUID(),
                    text: "Morning session",
                    x: 0.5,
                    y: 0.4,
                    scale: 1,
                    rotation: 0,
                    red: 1,
                    green: 1,
                    blue: 1,
                    alpha: 1,
                    alignment: "center",
                    background: false
                )
            ]
        )
        XCTAssertEqual(
            ContentDraftPreview.title(type: .story, payload: story),
            "Story • \"Morning session\""
        )
    }

    func testPayloadRoundTripAndRowMapping() throws {
        var payload = ContentDraftPayload()
        payload.trade = TradeComposerDraftState(
            symbol: "MNQ",
            side: TradeSide.short.rawValue,
            entryPrice: "21000",
            notes: "scaled out"
        )
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ContentDraftPayload.self, from: encoded)
        XCTAssertEqual(decoded.trade?.symbol, "MNQ")
        XCTAssertEqual(decoded.trade?.side, TradeSide.short.rawValue)
        XCTAssertEqual(decoded.trade?.notes, "scaled out")
        XCTAssertFalse(decoded.isMeaningfullyEmpty)

        let rowJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "draft_type": "post",
          "payload": {"version": 1, "post": {"body": "Hello", "imageStoragePath": null}},
          "created_at": "2026-10-05T19:15:00Z",
          "updated_at": "2026-10-05T19:16:00.123Z"
        }
        """
        let row = try JSONDecoder().decode(ContentDraftRowDTO.self, from: Data(rowJSON.utf8))
        let draft = try XCTUnwrap(ContentDraftRowMapping.draft(from: row))
        XCTAssertEqual(draft.type, .post)
        XCTAssertEqual(draft.payload.post?.body, "Hello")
        XCTAssertEqual(draft.userID.rawValue, "22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(
            ContentDraftPreview.title(type: draft.type, payload: draft.payload),
            "Post • \"Hello\""
        )
    }

    func testPublicationCleanupKeepsDraftUntilJobCompletes() async {
        let repository = ContentDraftCleanupSpy()
        let draftID = UUID()
        await MainActor.run {
            ContentDraftPublicationCleanup.shared.resetForTesting()
            ContentDraftPublicationCleanup.shared.track(
                jobID: "job-1",
                draftID: draftID,
                repository: repository
            )
        }
        let deletedBefore = await repository.deletedIDs
        XCTAssertTrue(deletedBefore.isEmpty)

        await ContentDraftPublicationCleanup.shared.noteJobCompleted("job-1")
        let deletedAfter = await repository.deletedIDs
        XCTAssertEqual(deletedAfter, [draftID])
    }
}

private actor ContentDraftCleanupSpy: ContentDraftRepository {
    private(set) var deletedIDs: [UUID] = []

    func listDrafts() async throws -> [ContentDraft] { [] }

    func saveDraft(_ draft: ContentDraft) async throws -> ContentDraft { draft }

    func deleteDraft(id: UUID) async throws {
        deletedIDs.append(id)
    }

    func uploadDraftImage(draftID: UUID, data: Data) async throws -> String { "image" }

    func uploadDraftVideo(draftID: UUID, fileURL: URL, contentType: String) async throws -> String { "video" }

    func deleteDraftMedia(paths: [String]) async {}
}
