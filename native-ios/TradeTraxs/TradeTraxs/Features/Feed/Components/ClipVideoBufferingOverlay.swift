import AVFoundation
import SwiftUI

/// Centered non-interactive buffering spinner for short-form clip playback surfaces.
struct ClipVideoBufferingOverlay: View {
    let player: AVPlayer?
    var suppressWhenUserPaused: Bool = false
    var suppressWhenReachedEnd: Bool = false

    @State private var model = ClipVideoBufferingModel()

    var body: some View {
        Group {
            if model.showsSpinner {
                ExperienceIndeterminateProgress(controlSize: .regular, tint: .white)
                    .scaleEffect(24 / 20)
                    .frame(width: 24, height: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { syncBinding() }
        .onDisappear { model.unbind() }
        .onChange(of: suppressWhenUserPaused) { _, _ in syncBinding() }
        .onChange(of: suppressWhenReachedEnd) { _, _ in syncBinding() }
        .onChange(of: playerIdentity) { _, _ in syncBinding() }
    }

    private var playerIdentity: ObjectIdentifier? {
        player.map(ObjectIdentifier.init)
    }

    private func syncBinding() {
        guard let player else {
            model.unbind()
            return
        }
        model.bind(
            player: player,
            suppressWhenUserPaused: suppressWhenUserPaused,
            suppressWhenReachedEnd: suppressWhenReachedEnd
        )
    }
}

@MainActor
@Observable
private final class ClipVideoBufferingModel {
    private(set) var showsSpinner = false

    private var suppressWhenUserPaused = false
    private var suppressWhenReachedEnd = false
    private weak var player: AVPlayer?
    private var boundPlayerID: ObjectIdentifier?
    private var playerObservations: [NSKeyValueObservation] = []
    private var itemObservations: [NSKeyValueObservation] = []
    private var stallObserver: NSObjectProtocol?
    private var showDelayTask: Task<Void, Never>?

    private static let showDelay: Duration = .milliseconds(200)

    /// KVO may fire off the main thread; marshal to the main actor without hopping `self` through concurrent `Task` captures.
    nonisolated private static func requestReevaluate(_ model: ClipVideoBufferingModel?) {
        DispatchQueue.main.async { [weak model] in
            MainActor.assumeIsolated {
                model?.reevaluate()
            }
        }
    }

    nonisolated private static func requestItemUpdate(
        _ model: ClipVideoBufferingModel?,
        item: AVPlayerItem?
    ) {
        DispatchQueue.main.async { [weak model] in
            MainActor.assumeIsolated {
                model?.bindCurrentItem(item)
                model?.reevaluate()
            }
        }
    }

    func bind(
        player: AVPlayer,
        suppressWhenUserPaused: Bool,
        suppressWhenReachedEnd: Bool
    ) {
        let id = ObjectIdentifier(player)
        let flagsChanged = self.suppressWhenUserPaused != suppressWhenUserPaused
            || self.suppressWhenReachedEnd != suppressWhenReachedEnd
        guard boundPlayerID != id || flagsChanged else {
            reevaluate()
            return
        }

        unbind()
        self.player = player
        boundPlayerID = id
        self.suppressWhenUserPaused = suppressWhenUserPaused
        self.suppressWhenReachedEnd = suppressWhenReachedEnd

        playerObservations = [
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
                Self.requestReevaluate(self)
            },
            player.observe(\.rate, options: [.new]) { [weak self] _, _ in
                Self.requestReevaluate(self)
            },
            player.observe(\.currentItem, options: [.initial, .new]) { [weak self] observed, _ in
                Self.requestItemUpdate(self, item: observed.currentItem)
            },
        ]
        bindCurrentItem(player.currentItem)
        reevaluate()
    }

    func unbind() {
        showDelayTask?.cancel()
        showDelayTask = nil
        playerObservations.forEach { $0.invalidate() }
        itemObservations.forEach { $0.invalidate() }
        playerObservations = []
        itemObservations = []
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
            self.stallObserver = nil
        }
        player = nil
        boundPlayerID = nil
        showsSpinner = false
    }

    private func bindCurrentItem(_ item: AVPlayerItem?) {
        itemObservations.forEach { $0.invalidate() }
        itemObservations = []
        if let stallObserver {
            NotificationCenter.default.removeObserver(stallObserver)
            self.stallObserver = nil
        }
        guard let item else { return }

        itemObservations = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                Self.requestReevaluate(self)
            },
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] _, _ in
                Self.requestReevaluate(self)
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] _, _ in
                Self.requestReevaluate(self)
            },
        ]

        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Self.requestReevaluate(self)
        }
    }

    private func applyDelayedSpinnerIfStillBuffering() {
        guard computeRawBuffering() else { return }
        showsSpinner = true
    }

    private func reevaluate() {
        let wantsSpinner = computeRawBuffering()
        if wantsSpinner {
            guard !showsSpinner else { return }
            showDelayTask?.cancel()
            showDelayTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.showDelay)
                guard !Task.isCancelled else { return }
                self?.applyDelayedSpinnerIfStillBuffering()
            }
        } else {
            showDelayTask?.cancel()
            showDelayTask = nil
            showsSpinner = false
        }
    }

    private func computeRawBuffering() -> Bool {
        guard let player, !suppressWhenUserPaused, !suppressWhenReachedEnd else { return false }
        guard player.currentItem != nil else { return false }

        switch player.timeControlStatus {
        case .waitingToPlayAtSpecifiedRate:
            return true
        case .paused:
            return false
        case .playing:
            guard let item = player.currentItem else { return false }
            if item.status == .failed { return false }
            return item.isPlaybackBufferEmpty && !item.isPlaybackLikelyToKeepUp
        @unknown default:
            return false
        }
    }
}