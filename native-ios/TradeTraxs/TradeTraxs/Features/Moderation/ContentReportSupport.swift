import Foundation

extension DetailContentLink {
    func reportTarget(ownerID: ProfileID) -> ContentReportTarget {
        switch self {
        case .trade(let id):
            return .trade(id, ownerID: ownerID)
        case .post(let id):
            return .post(id, ownerID: ownerID)
        case .reel(let id):
            return .reel(id, ownerID: ownerID)
        case .achievement(let id):
            return .achievement(id, ownerID: ownerID)
        case .story(let id):
            return .story(id, ownerID: ownerID)
        }
    }

    var reportSubjectTitle: String {
        switch self {
        case .trade: return "this trade"
        case .post: return "this post"
        case .reel: return "this clip"
        case .achievement: return "this achievement"
        case .story: return "this story"
        }
    }
}

enum ContentReportSupport {
    @MainActor
    static func presentUser(
        profileID: ProfileID,
        displayName: String?,
        presenter: ContentReportPresenter
    ) {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = (name?.isEmpty == false) ? name! : "this user"
        presenter.present(
            ContentReportRequest(
                target: .user(profileID),
                subjectTitle: subject,
                blockUserOffer: profileID
            )
        )
    }

    @MainActor
    static func presentComment(
        comment: InteractionComment,
        presenter: ContentReportPresenter
    ) {
        let author = comment.authorUsername.map { "@\($0)" }
            ?? comment.authorDisplayName
            ?? "this comment"
        presenter.present(
            ContentReportRequest(
                target: .comment(comment.id, authorID: comment.authorProfileID),
                subjectTitle: author,
                blockUserOffer: comment.authorProfileID
            )
        )
    }

    @MainActor
    static func presentDirectMessage(
        message: Message,
        presenter: ContentReportPresenter
    ) {
        presenter.present(
            ContentReportRequest(
                target: .directMessage(message.id, senderID: message.senderProfileID),
                subjectTitle: "this message",
                blockUserOffer: message.senderProfileID
            )
        )
    }

    @MainActor
    static func presentTradeRoom(
        roomID: RoomID,
        roomName: String?,
        ownerID: ProfileID?,
        presenter: ContentReportPresenter
    ) {
        let name = roomName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = (name?.isEmpty == false) ? name! : "this trade room"
        presenter.present(
            ContentReportRequest(
                target: .tradeRoom(roomID, ownerID: ownerID),
                subjectTitle: subject,
                blockUserOffer: ownerID
            )
        )
    }

    @MainActor
    static func presentTradeRoomMessage(
        message: Message,
        presenter: ContentReportPresenter
    ) {
        presenter.present(
            ContentReportRequest(
                target: .tradeRoomMessage(
                    RoomMessageID(message.id.rawValue),
                    senderID: message.senderProfileID
                ),
                subjectTitle: "this message",
                blockUserOffer: message.senderProfileID
            )
        )
    }
}
