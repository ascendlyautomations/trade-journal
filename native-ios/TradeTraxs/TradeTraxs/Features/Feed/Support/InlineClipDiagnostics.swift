import CoreGraphics
import Foundation

#if DEBUG
enum InlineClipDiagnostics {
    static func log(
        clipID: String,
        visibleFraction: CGFloat,
        candidate: Bool,
        active: Bool,
        playerAction: String,
        mute: Bool,
        reason: String
    ) {
        print(
            """
            [InlineClip] clipID=\(clipID) visibleFraction=\(String(format: "%.2f", visibleFraction)) \
            candidate=\(candidate) active=\(active) playerAction=\(playerAction) \
            mute=\(mute) reason=\(reason)
            """
        )
    }
}

enum InlineClipOwnershipDiagnostics {
    static func log(
        from: String?,
        to: String?,
        reason: String,
        currentVisibility: CGFloat,
        candidateVisibility: CGFloat
    ) {
        print(
            """
            [InlineClipOwnership] from=\(from ?? "nil") to=\(to ?? "nil") reason=\(reason) \
            currentVisibility=\(String(format: "%.2f", currentVisibility)) \
            candidateVisibility=\(String(format: "%.2f", candidateVisibility))
            """
        )
    }
}

enum InlineClipAudioDiagnostics {
    static func log(
        clipID: String,
        action: String,
        before: Bool,
        after: Bool,
        isPlaying: Bool
    ) {
        print(
            """
            [InlineClipAudio] clipID=\(clipID) action=\(action) before=\(before) after=\(after) \
            isPlaying=\(isPlaying)
            """
        )
    }
}

enum InlineClipFreezeDiagnostics {
    static func log(
        clipID: String,
        action: String,
        playbackTime: Double,
        frameAvailable: Bool,
        reason: String
    ) {
        print(
            """
            [InlineClipFreeze] clipID=\(clipID) action=\(action) \
            playbackTime=\(String(format: "%.2f", playbackTime)) frameAvailable=\(frameAvailable) \
            reason=\(reason)
            """
        )
    }
}

enum InlineClipPresentationDiagnostics {
    static func log(
        clipID: String,
        sourceSize: String,
        orientedSize: String,
        aspectRatio: CGFloat,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        gravity: String
    ) {
        print(
            """
            [InlineClipPresentation] clipID=\(clipID) sourceSize=\(sourceSize) \
            orientedSize=\(orientedSize) aspectRatio=\(String(format: "%.4f", aspectRatio)) \
            containerWidth=\(String(format: "%.1f", containerWidth)) \
            containerHeight=\(String(format: "%.1f", containerHeight)) gravity=\(gravity)
            """
        )
    }
}

enum InlineClipRenderFrameDiagnostics {
    static func log(
        clipID: String,
        swiftUIContainer: CGSize,
        uiViewBounds: CGRect,
        playerLayerFrame: CGRect,
        videoRect: CGRect,
        gravity: String,
        presentationSize: CGSize?,
        naturalSize: CGSize?,
        preferredTransform: String?
    ) {
        let presentationText: String
        if let presentationSize, presentationSize.width > 0, presentationSize.height > 0 {
            presentationText = "\(Int(presentationSize.width))x\(Int(presentationSize.height))"
        } else {
            presentationText = "n/a"
        }
        let naturalText: String
        if let naturalSize, naturalSize.width > 0, naturalSize.height > 0 {
            naturalText = "\(Int(naturalSize.width))x\(Int(naturalSize.height))"
        } else {
            naturalText = "n/a"
        }
        print(
            """
            [InlineClipRenderFrame] clipID=\(clipID) \
            swiftUIContainer=\(Int(swiftUIContainer.width))x\(Int(swiftUIContainer.height)) \
            uiViewBounds=\(Int(uiViewBounds.width))x\(Int(uiViewBounds.height)) \
            playerLayerFrame=\(Int(playerLayerFrame.width))x\(Int(playerLayerFrame.height)) \
            videoRect=\(Int(videoRect.width))x\(Int(videoRect.height)) \
            gravity=\(gravity) presentationSize=\(presentationText) naturalSize=\(naturalText) \
            preferredTransform=\(preferredTransform ?? "n/a")
            """
        )
    }
}

enum InlineClipPlaybackDiagnostics {
    static func log(
        clipID: String,
        action: String,
        reason: String,
        activeClipID: String?,
        visibility: CGFloat?,
        appLifecycle: String = "active",
        userInitiated: Bool
    ) {
        let visibilityText: String
        if let visibility {
            visibilityText = String(format: "%.2f", visibility)
        } else {
            visibilityText = "n/a"
        }
        print(
            """
            [InlineClipPlayback] clipID=\(clipID) action=\(action) reason=\(reason) \
            activeClipID=\(activeClipID ?? "nil") visibility=\(visibilityText) \
            appLifecycle=\(appLifecycle) userInitiated=\(userInitiated)
            """
        )
    }
}
#else
enum InlineClipDiagnostics {
    static func log(
        clipID: String,
        visibleFraction: CGFloat,
        candidate: Bool,
        active: Bool,
        playerAction: String,
        mute: Bool,
        reason: String
    ) {}
}

enum InlineClipOwnershipDiagnostics {
    static func log(
        from: String?,
        to: String?,
        reason: String,
        currentVisibility: CGFloat,
        candidateVisibility: CGFloat
    ) {}
}

enum InlineClipAudioDiagnostics {
    static func log(
        clipID: String,
        action: String,
        before: Bool,
        after: Bool,
        isPlaying: Bool
    ) {}
}

enum InlineClipFreezeDiagnostics {
    static func log(
        clipID: String,
        action: String,
        playbackTime: Double,
        frameAvailable: Bool,
        reason: String
    ) {}
}

enum InlineClipPresentationDiagnostics {
    static func log(
        clipID: String,
        sourceSize: String,
        orientedSize: String,
        aspectRatio: CGFloat,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        gravity: String
    ) {}
}

enum InlineClipRenderFrameDiagnostics {
    static func log(
        clipID: String,
        swiftUIContainer: CGSize,
        uiViewBounds: CGRect,
        playerLayerFrame: CGRect,
        videoRect: CGRect,
        gravity: String,
        presentationSize: CGSize?,
        naturalSize: CGSize?,
        preferredTransform: String?
    ) {}
}

enum InlineClipPlaybackDiagnostics {
    static func log(
        clipID: String,
        action: String,
        reason: String,
        activeClipID: String?,
        visibility: CGFloat?,
        appLifecycle: String = "active",
        userInitiated: Bool
    ) {}
}
#endif
