import SwiftUI

enum RoomBroadcastCornerPlayerSize {
  /// Keyboard + default overlay
  case standard
  /// Manual corner pin while reading chat
  case compact

  var width: CGFloat {
    switch self {
    case .standard: return 136
    case .compact: return 92
    }
  }
}

/// Viewer-only: program video floating top-trailing while the chat composer is focused.
struct RoomBroadcastChatTypingMiniPlayer: View {
  @Bindable var coordinator: RoomBroadcastCoordinator
  var size: RoomBroadcastCornerPlayerSize = .standard
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var width: CGFloat { size.width }

  private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black
            BroadcastStreamZoomableVideoView(
                track: coordinator.videoTrackForExpandedViewer,
                isFullscreen: false,
                onFirstFrame: { coordinator.markProgramVideoFrameRendered() }
            )
            .id(coordinator.programVideoTrackRevision)
            .opacity(coordinator.hasDisplayableProgramVideo ? 1 : 0)

            if let placeholder = coordinator.programVideoPlaceholder {
                BroadcastProgramVideoPlaceholderOverlay(presentation: placeholder, compact: true)
            }

            RoomBroadcastStreamPlaybackMuteButton(coordinator: coordinator)
                .padding(ExperienceSpacing.xxs)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        .accessibilityIdentifier("tradeRooms.broadcast.video.chatMini")
        .accessibilityLabel("Live stream playing")
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.28),
            value: coordinator.programVideoTrackRevision
        )
    }
}

/// Full-width chat host + floating mini player (does not inset message layout).
struct RoomBroadcastChatTypingMiniPlayerOverlay: View {
  @Bindable var coordinator: RoomBroadcastCoordinator
  @Binding var isDismissed: Bool
  var size: RoomBroadcastCornerPlayerSize = .standard
  var onExpand: (() -> Void)?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffsetX: CGFloat = 0

    private let dismissDistance: CGFloat = 88
    private let offscreenOffset: CGFloat = 220

  var body: some View {
      RoomBroadcastChatTypingMiniPlayer(coordinator: coordinator, size: size)
          .overlay(alignment: .topLeading) {
              if let onExpand, isVisible {
                  Button(action: onExpand) {
                      Image(systemName: "arrow.up.left.and.arrow.down.right")
                          .font(.system(size: 10, weight: .bold))
                          .foregroundStyle(.white)
                          .padding(5)
                          .background(Color.black.opacity(0.55), in: Circle())
                  }
                  .buttonStyle(.experiencePlain)
                  .padding(4)
                  .accessibilityLabel("Expand video")
              }
          }
          .offset(x: horizontalOffset)
          .opacity(Double(1 - dismissalProgress * 0.92))
          .allowsHitTesting(isVisible)
          .padding(.top, ExperienceSpacing.xs)
          .padding(.trailing, ExperienceSpacing.sm)
          .gesture(swipeAwayGesture)
          .accessibilityHidden(!isVisible)
          .transition(
              .scale(scale: 0.92, anchor: .topTrailing)
                  .combined(with: .opacity)
          )
  }

    private var isVisible: Bool {
        !isDismissed
    }

    private var horizontalOffset: CGFloat {
        if isDismissed {
            return offscreenOffset
        }
        return max(0, dragOffsetX)
    }

    private var dismissalProgress: CGFloat {
        if isDismissed { return 1 }
        return min(1, max(0, dragOffsetX / dismissDistance))
    }

    private var swipeAwayGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard horizontal > 0, horizontal > vertical * 0.65 else { return }
                dragOffsetX = horizontal
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let flick = value.predictedEndTranslation.width - horizontal
                let shouldDismiss = horizontal >= dismissDistance || flick > 120
                if shouldDismiss {
                    let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.28)
                    withAnimation(animation) {
                        isDismissed = true
                        dragOffsetX = 0
                    }
                    ExperienceHaptics.play(.selection)
                } else {
                    let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.22)
                    withAnimation(animation) {
                        dragOffsetX = 0
                    }
                }
            }
    }
}