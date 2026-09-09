import Foundation
import Observation

@Observable
@MainActor
final class TradeRoomJoinRequestDetailViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let requestID: String

    private(set) var phase: Phase = .idle
    private(set) var requester: Profile?
    private(set) var room: TradeRoom?
    private(set) var status: TradeRoomJoinRequestState = .pending
    private(set) var canResolve = false
    private(set) var createdAt: Date?
    var statusMessage: String?
    var isMutating = false

    private let rooms: any RoomRepository
    private let profiles: any ProfileRepository
    private let supabase: SupabaseInfrastructure
    private let navigationCoordinator: NavigationCoordinator?
    private let navigationHost: TradeRoomNavigationHost

    init(
        requestID: String,
        rooms: any RoomRepository,
        profiles: any ProfileRepository,
        supabase: SupabaseInfrastructure,
        navigationCoordinator: NavigationCoordinator? = nil,
        navigationHost: TradeRoomNavigationHost = .messages
    ) {
        self.requestID = requestID
        self.rooms = rooms
        self.profiles = profiles
        self.supabase = supabase
        self.navigationCoordinator = navigationCoordinator
        self.navigationHost = navigationHost
    }

    var resolvedStatusLabel: String? {
        switch status {
        case .pending:
            return nil
        case .approved:
            return "Accepted"
        case .rejected:
            return "Declined"
        }
    }

    func loadIfNeeded() {
        guard phase != .loaded else { return }
        phase = .loading
        Task { await performLoad() }
    }

    func retry() {
        phase = .idle
        loadIfNeeded()
    }

    func openRequester() {
        guard let requester else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.profile(requester.id))
    }

    func openRoom() {
        guard let room else { return }
        ExperienceHaptics.play(.selection)
        navigationCoordinator?.open(navigationHost.room(room.id))
    }

    func approve() async {
        await resolve(action: .approve)
    }

    func decline() async {
        await resolve(action: .decline)
    }

    private func resolve(action: TradeRoomJoinRequestResolution) async {
        guard canResolve, !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            guard let management = rooms as? any RoomManagementRepository else {
                throw AppError.unknown(message: "Join request management is unavailable.")
            }
            try await management.resolveJoinRequest(requestID: requestID, action: action)
            status = action == .approve ? .approved : .rejected
            canResolve = false
            statusMessage = action == .approve ? "Join request approved." : "Join request declined."
            ExperienceHaptics.play(.success)
            AppIconBadgeSync.refresh(animated: true)
        } catch {
            statusMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.error)
        }
    }

    private func performLoad() async {
        do {
            struct Params: Encodable { var p_request_id: String }
            let data = try await supabase.database.rpcData(
                functionName: "rpc_v1_trade_room_join_request_detail",
                parametersJSON: try JSONEncoder().encode(Params(p_request_id: requestID))
            )
            let detail = try JSONDecoder().decode(DetailWire.self, from: data)
            status = TradeRoomJoinRequestState.parse(detail.status) ?? .pending
            canResolve = detail.can_resolve == true && status == .pending
            createdAt = ISO8601.date(from: detail.created_at ?? "")

            if let roomWire = detail.room, let roomID = roomWire.id {
                room = TradeRoom(
                    id: RoomID(roomID),
                    ownerProfileID: ProfileID("official.\(roomID)"),
                    name: roomWire.name ?? "Trade Room",
                    slug: roomWire.slug ?? roomID,
                    description: nil,
                    image: roomWire.image_url.map { MediaReference(id: $0, kind: .image, altText: nil) },
                    memberCount: nil,
                    showsOnProfile: true,
                    roomKind: TradeRoomKind.parse(roomWire.room_kind),
                    createdAt: .now
                )
            }

            if let requesterWire = detail.requester, let profileID = requesterWire.id {
                requester = Profile(
                    id: ProfileID(profileID),
                    userID: UserID(profileID),
                    username: requesterWire.username ?? profileID,
                    displayName: requesterWire.name ?? requesterWire.username ?? "Trader",
                    bio: nil,
                    avatar: requesterWire.avatar_url.map {
                        MediaReference(id: $0, kind: .image, altText: nil)
                    },
                    traderType: nil,
                    tradingStyle: nil,
                    primaryMarket: nil,
                    startedTradingAt: nil,
                    isPrivate: false,
                    isCreator: false,
                    createdAt: .now
                )
            } else if let userID = detail.user_id {
                requester = try? await profiles.profile(id: ProfileID(userID))
            }

            phase = .loaded
        } catch {
            phase = .failed(ProfileSectionSupport.message(for: error))
        }
    }

    private struct DetailWire: Decodable {
        var id: String?
        var room_id: String?
        var user_id: String?
        var status: String?
        var created_at: String?
        var can_resolve: Bool?
        var room: RoomWire?
        var requester: RequesterWire?
    }

    private struct RoomWire: Decodable {
        var id: String?
        var name: String?
        var slug: String?
        var image_url: String?
        var room_kind: String?
    }

    private struct RequesterWire: Decodable {
        var id: String?
        var username: String?
        var name: String?
        var avatar_url: String?
    }
}
