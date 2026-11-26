import SwiftUI
import UIKit

/// Compact avatar for follow lists, reuses the shared image pipeline / memory cache.
struct FollowListAvatarView: View {
    let profile: Profile
    let imagePipeline: any ImagePipeline
    var size: CGFloat = 48
    /// DEBUG audit label (`activity`, `feed`, …).
    var debugSurface: String = "followList"

    @State private var image: Image?

    private var maxPixelSize: Int {
        ProfileAvatarDisplayCache.listMaxPixelSize(diameter: size)
    }

    init(
        profile: Profile,
        imagePipeline: any ImagePipeline,
        size: CGFloat = 48,
        debugSurface: String = "followList"
    ) {
        self.profile = profile
        self.imagePipeline = imagePipeline
        self.size = size
        self.debugSurface = debugSurface
        if let key = ProfileAvatarDisplayCache.cacheKey(
            profile: profile,
            maxPixelSize: ProfileAvatarDisplayCache.listMaxPixelSize(diameter: size)
        ),
           let ui = ProfileAvatarDisplayCache.uiImage(forKey: key)
        {
            _image = State(initialValue: Image(uiImage: ui))
        } else {
            _image = State(initialValue: nil)
        }
    }

    var body: some View {
        ExperienceAvatar(
            initials: ProfileDisplay.initials(
                displayName: profile.displayName,
                username: profile.username
            ),
            image: image,
            size: size
        )
        .task(id: loadTaskID) {
            await load()
        }
    }

    private var loadTaskID: String {
        if let key = ProfileAvatarDisplayCache.cacheKey(profile: profile, maxPixelSize: maxPixelSize) {
            return key
        }
        return profile.id.rawValue
    }

    private func load() async {
        guard let cacheKey = ProfileAvatarDisplayCache.cacheKey(
            profile: profile,
            maxPixelSize: maxPixelSize
        ) else {
            image = nil
            return
        }

        if let ui = ProfileAvatarDisplayCache.uiImage(forKey: cacheKey) {
            image = Image(uiImage: ui)
            #if DEBUG
            ProfileAvatarLoadDiagnostics.log(
                surface: debugSurface,
                profileID: profile.id.rawValue,
                cacheKey: cacheKey,
                source: .displayMemory
            )
            #endif
            return
        }

        image = nil

        guard let reference = profile.avatar else {
            return
        }

        let request = ImageRequest(
            reference: reference,
            purpose: .profileAvatar,
            maxPixelSize: maxPixelSize,
            auditSurface: debugSurface,
            auditMediaID: profile.id.rawValue
        )

        if let cached = await imagePipeline.bestCachedImageDataWithTier(for: request) {
            applyLoadedData(
                cached.data,
                cacheKey: cacheKey,
                source: cached.tier == .memory ? .pipelineMemory : .pipelineDisk
            )
            return
        }

        do {
            let data = try await imagePipeline.data(for: request)
            applyLoadedData(data, cacheKey: cacheKey, source: .network)
        } catch {
            image = nil
        }
    }

    private enum LoadSource {
        case displayMemory
        case pipelineMemory
        case pipelineDisk
        case network
    }

    private func applyLoadedData(
        _ data: Data,
        cacheKey: String,
        source: LoadSource
    ) {
        guard let ui = UIImage(data: data) else {
            image = nil
            return
        }
        let normalized = MediaImageOrientation.normalized(ui)
        ProfileAvatarDisplayCache.store(normalized, forKey: cacheKey)
        image = Image(uiImage: normalized)
        #if DEBUG
        let mapped: ProfileAvatarLoadDiagnostics.Source = switch source {
        case .displayMemory: .displayMemory
        case .pipelineMemory: .pipelineMemory
        case .pipelineDisk: .pipelineDisk
        case .network: .network
        }
        ProfileAvatarLoadDiagnostics.log(
            surface: debugSurface,
            profileID: profile.id.rawValue,
            cacheKey: cacheKey,
            source: mapped
        )
        #endif
    }
}
