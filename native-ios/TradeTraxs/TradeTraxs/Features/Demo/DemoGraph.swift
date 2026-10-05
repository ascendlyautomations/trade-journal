import Foundation

/// One Demo Mode entity graph. Journal numbers stay on ``DemoCanonicalDataset``.
/// Social rows, activity, messages, and rooms reference those same trades and profiles.
nonisolated enum DemoGraph {
    static let alexID = ProfileID("demo.profile.alex")
    static let sarahID = ProfileID("demo.profile.sarah")
    static let mikeID = ProfileID("demo.profile.mike")
    static let postID = PostID("demo.post.session")
    static let notePostID = PostID("demo.post.note")
    static let clipID = ReelID("demo.clip.open")
    static let achievementID = AchievementID("demo.achievement.payout")
    static let sarahConversationID = ConversationID("demo.dm.sarah")
    static let reportID = ReportID("monthly_last")

    private static let chartURL =
        "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&q=80"

    static func featuredTrade() -> Trade {
        let trades = DemoCanonicalDataset.trades()
        return trades.first { $0.visibility == .public } ?? trades[0]
    }

    static func profile(id: ProfileID) -> Profile? {
        if id == DemoExperienceSupport.profileID {
            return DemoCanonicalDataset.profile()
        }
        if id == DemoExploreTradeRoom.hostProfileID {
            return DemoExploreTradeRoom.hostProfile()
        }
        return profiles().first { $0.id == id }
    }

    static func profiles() -> [Profile] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.peers
        }
        return [
            makeProfile(id: alexID, username: "alex", name: "Alex Rivera", style: "Opening drive"),
            makeProfile(id: sarahID, username: "sarah", name: "Sarah Chen", style: "Liquidity sweep"),
            makeProfile(id: mikeID, username: "mike", name: "Mike Alvarez", style: "VWAP rejection"),
        ]
    }

    static func followers() -> [Profile] {
        profiles()
    }

    static func following() -> [Profile] {
        [profile(id: sarahID), profile(id: alexID)].compactMap { $0 }
    }

    static func posts(owner: ProfileID = DemoExperienceSupport.profileID) -> [Post] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.posts.map { post in
                var copy = post
                copy.authorProfileID = owner
                return copy
            }
        }
        let trade = featuredTrade()
        let now = Date()
        return [
            Post(
                id: postID,
                authorProfileID: owner,
                body: "\(trade.symbol.ticker) \(trade.side == .long ? "long" : "short") — logged on the \(trade.sessionLabel ?? "session") plan.",
                media: [MediaReference(id: chartURL, kind: .image, altText: "Session chart")],
                visibility: .public,
                linkedTradeID: trade.id,
                isPinned: true,
                createdAt: trade.createdAt,
                updatedAt: trade.updatedAt
            ),
            Post(
                id: notePostID,
                authorProfileID: owner,
                body: "Process note: size stayed inside the plan after the first loss.",
                media: [],
                visibility: .public,
                linkedTradeID: nil,
                isPinned: false,
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-86_400)
            ),
        ]
    }

    static func post(id: PostID) -> Post? {
        posts().first { $0.id == id }
    }

    static func clips(owner: ProfileID = DemoExperienceSupport.profileID) -> [Reel] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.clips.map { clip in
                var copy = clip
                copy.authorProfileID = owner
                return copy
            }
        }
        let trade = featuredTrade()
        return [
            Reel(
                id: clipID,
                authorProfileID: owner,
                video: MediaReference(
                    id: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4",
                    kind: .video,
                    altText: nil
                ),
                thumbnail: MediaReference(id: chartURL, kind: .image, altText: "Clip"),
                caption: "\(trade.symbol.ticker) recap",
                visibility: .public,
                linkedTradeID: trade.id,
                durationSeconds: 10,
                createdAt: trade.createdAt
            ),
        ]
    }

    static func achievements(owner: ProfileID = DemoExperienceSupport.profileID) -> [Achievement] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.achievements.map { achievement in
                var copy = achievement
                copy.ownerProfileID = owner
                return copy
            }
        }
        let now = Date()
        return [
            Achievement(
                id: achievementID,
                ownerProfileID: owner,
                kind: .propFirmPayout,
                title: "Funded payout",
                description: "Payout recorded on the Apex 50K Funded account.",
                tier: .gold,
                value: Money(amount: 1_850),
                valueText: nil,
                firm: "Apex",
                accountID: DemoCanonicalDataset.fundedAccountID,
                image: MediaReference(id: chartURL, kind: .image, altText: "Payout"),
                isPublic: true,
                isFeatured: true,
                sortOrder: 0,
                achievedAt: now.addingTimeInterval(-86_400 * 18)
            ),
        ]
    }

    static func stories(viewerID: ProfileID = DemoExperienceSupport.profileID) -> [Story] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.stories
        }
        let now = Date()
        let authors: [ProfileID] = [sarahID, alexID, viewerID]
        return authors.enumerated().map { index, author in
            Story(
                id: StoryID("demo.story.\(author.rawValue)"),
                authorProfileID: author,
                media: MediaReference(id: chartURL, kind: .image, altText: "Story"),
                expiresAt: now.addingTimeInterval(86_400),
                createdAt: now.addingTimeInterval(TimeInterval(-900 * (index + 1))),
                viewerHasSeen: author == viewerID
            )
        }
    }

    static func feedEntries(viewerID: ProfileID) -> [FeedTimelineEntry] {
        let trade = featuredTrade()
        let summary = TradeSummaryMapper.summary(fromPartialListTrade: trade)
        let post = posts(owner: viewerID)[0]
        let note = posts(owner: viewerID)[1]
        let clip = clips(owner: sarahID)[0]
        let achievement = achievements(owner: viewerID)[0]
        return FeedSupport.sortDescending([
            .trade(
                feedItem(
                    id: "feed-\(trade.id.rawValue)",
                    kind: .trade,
                    authorProfileID: trade.ownerProfileID,
                    createdAt: trade.createdAt,
                    tradeID: trade.id,
                    caption: trade.publicCaption
                ),
                summary
            ),
            .post(
                feedItem(
                    id: "feed-\(post.id.rawValue)",
                    kind: .post,
                    authorProfileID: post.authorProfileID,
                    createdAt: post.createdAt,
                    postID: post.id,
                    caption: post.body
                ),
                post
            ),
            .post(
                feedItem(
                    id: "feed-\(note.id.rawValue)",
                    kind: .post,
                    authorProfileID: note.authorProfileID,
                    createdAt: note.createdAt,
                    postID: note.id,
                    caption: note.body
                ),
                note
            ),
            .clip(
                feedItem(
                    id: "feed-\(clip.id.rawValue)",
                    kind: .reel,
                    authorProfileID: clip.authorProfileID,
                    createdAt: clip.createdAt,
                    reelID: clip.id,
                    caption: clip.caption
                ),
                clip
            ),
            .achievement(
                feedItem(
                    id: "feed-\(achievement.id.rawValue)",
                    kind: .achievement,
                    authorProfileID: achievement.ownerProfileID,
                    createdAt: achievement.achievedAt,
                    achievementID: achievement.id,
                    caption: achievement.title
                ),
                achievement
            ),
        ])
    }

    static func traders(excluding viewerID: ProfileID) -> [ExploreTraderSuggestion] {
        profiles().filter { $0.id != viewerID }.enumerated().map { index, profile in
            ExploreTraderSuggestion(
                profile: profile,
                followerCount: 120 - (index * 15),
                score: 80 - index,
                identityLine: profile.tradingStyle
            )
        }
    }

    static func notifications(now: Date = Date()) -> [ActivityNotification] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.activity
        }
        let trade = featuredTrade()
        return [
            notification(
                id: "demo.activity.like",
                kind: .like,
                actor: alexID,
                tradeID: trade.id,
                createdAt: now.addingTimeInterval(-600),
                isRead: false
            ),
            notification(
                id: "demo.activity.follow",
                kind: .follow,
                actor: sarahID,
                createdAt: now.addingTimeInterval(-3_600),
                isRead: false
            ),
            notification(
                id: "demo.activity.comment",
                kind: .comment,
                actor: mikeID,
                body: "Clean process note.",
                postID: notePostID,
                createdAt: now.addingTimeInterval(-7_200),
                isRead: true
            ),
            notification(
                id: "demo.activity.room",
                kind: .roomMention,
                actor: alexID,
                roomID: DemoExploreTradeRoom.roomID,
                roomSlug: "tradetraxs-traders",
                roomName: "TradeTraxs Traders",
                sectionName: "General",
                messagePreview: "Check the MNQ recap",
                createdAt: now.addingTimeInterval(-14_000),
                isRead: true
            ),
            notification(
                id: "demo.activity.report",
                kind: .tradingReport,
                title: "Monthly trading report",
                body: "Your monthly summary is ready",
                reportID: reportID,
                createdAt: now.addingTimeInterval(-86_400),
                isRead: true
            ),
        ]
    }

    static func conversations(viewerID: ProfileID) -> [Conversation] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.conversations
        }
        let sarah = profile(id: sarahID)
        let now = Date()
        let trade = featuredTrade()
        return [
            Conversation(
                id: sarahConversationID,
                participantProfileIDs: [viewerID, sarahID],
                title: sarah?.displayName,
                peerUsername: sarah?.username,
                avatar: sarah?.avatar,
                isGroup: false,
                isPinned: true,
                lastMessagePreview: "Shared \(trade.symbol.ticker)",
                lastMessageAt: now.addingTimeInterval(-900),
                unreadCount: 1,
                isMuted: false,
                updatedAt: now.addingTimeInterval(-900)
            ),
        ]
    }

    static func messages(conversationID: ConversationID, viewerID: ProfileID) -> [Message] {
        if let snapshot = DemoSnapshotStore.shared.current {
            return snapshot.messages.filter { $0.conversationID == conversationID }
        }
        guard conversationID == sarahConversationID else { return [] }
        let trade = featuredTrade()
        let now = Date()
        return [
            Message(
                id: MessageID("\(conversationID.rawValue).hello"),
                conversationID: conversationID,
                senderProfileID: sarahID,
                kind: .text,
                body: "That \(trade.symbol.ticker) is the one from your journal.",
                attachments: [],
                replyToMessageID: nil,
                createdAt: now.addingTimeInterval(-1_800),
                isReadByViewer: true
            ),
            Message(
                id: MessageID("\(conversationID.rawValue).trade"),
                conversationID: conversationID,
                senderProfileID: sarahID,
                kind: .tradeShare,
                body: nil,
                attachments: [],
                replyToMessageID: nil,
                createdAt: now.addingTimeInterval(-900),
                isReadByViewer: false,
                sharedContent: SharedContentReference.trade(trade.id)
            ),
        ]
    }

    @MainActor
    static func seedActivity(_ store: ActivityInboxStore, cache: DetailPresentationCache?) {
        let items = notifications()
        store.replace(
            items: items,
            unreadCount: items.filter { !$0.isRead }.count,
            nextCursor: nil,
            pendingFollowRequestCount: 0
        )
        for profile in profiles() {
            cache?.seed(profile)
        }
        cache?.seed(DemoCanonicalDataset.profile())
        cache?.seed(trades: [featuredTrade()])
    }

    @MainActor
    static func seedFeedCache(_ cache: DetailPresentationCache, viewerID: ProfileID) {
        cache.seed(DemoCanonicalDataset.profile())
        for profile in profiles() {
            cache.seed(profile)
        }
        cache.seed(DemoExploreTradeRoom.hostProfile())
        cache.seed(trades: DemoCanonicalDataset.trades())
        cache.seed(achievements: achievements(owner: viewerID))
    }

    private static func feedItem(
        id: String,
        kind: FeedItemKind,
        authorProfileID: ProfileID,
        createdAt: Date,
        tradeID: TradeID? = nil,
        postID: PostID? = nil,
        reelID: ReelID? = nil,
        achievementID: AchievementID? = nil,
        caption: String?
    ) -> FeedItem {
        let author = profile(id: authorProfileID)
        return FeedItem(
            id: id,
            kind: kind,
            authorProfileID: authorProfileID,
            createdAt: createdAt,
            tradeID: tradeID,
            postID: postID,
            reelID: reelID,
            storyID: nil,
            achievementID: achievementID,
            caption: caption,
            likeCount: 12,
            commentCount: 3,
            viewerHasLiked: false,
            authorUsername: author?.username,
            authorDisplayName: author?.displayName,
            authorAvatarURL: author?.avatar?.id,
            mediaURL: chartURL
        )
    }

    private static func makeProfile(
        id: ProfileID,
        username: String,
        name: String,
        style: String
    ) -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: username,
            displayName: name,
            bio: "Demo trader. \(style).",
            avatar: nil,
            traderType: .futures,
            tradingStyle: style,
            primaryMarket: "NQ",
            startedTradingAt: Date(timeIntervalSince1970: 1_704_067_200),
            isPrivate: false,
            isCreator: false,
            createdAt: Date(timeIntervalSince1970: 1_704_067_200)
        )
    }

    private static func notification(
        id: String,
        kind: ActivityNotificationKind,
        actor: ProfileID? = nil,
        title: String = "",
        body: String = "",
        tradeID: TradeID? = nil,
        postID: PostID? = nil,
        roomID: RoomID? = nil,
        roomSlug: String? = nil,
        roomName: String? = nil,
        sectionName: String? = nil,
        messagePreview: String? = nil,
        reportID: ReportID? = nil,
        createdAt: Date,
        isRead: Bool
    ) -> ActivityNotification {
        ActivityNotification(
            id: NotificationID(id),
            kind: kind,
            actorProfileID: actor,
            title: title.isEmpty ? kind.rawValue : title,
            body: body,
            tradeID: tradeID,
            postID: postID,
            profilePostID: nil,
            achievementPostID: nil,
            reelID: nil,
            commentID: nil,
            conversationID: nil,
            roomID: roomID,
            roomMessageID: nil,
            followRequestID: nil,
            joinRequestID: nil,
            joinRequestStatus: nil,
            roomSlug: roomSlug,
            roomName: roomName,
            sectionID: nil,
            sectionName: sectionName,
            messagePreview: messagePreview,
            reportID: reportID,
            affiliateHref: nil,
            isReply: false,
            isMention: kind == .roomMention,
            createdAt: createdAt,
            isRead: isRead
        )
    }
}
