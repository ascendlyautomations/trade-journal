import SwiftUI

struct ClipsContainerView: View {
    @Bindable var viewModel: ClipsContainerViewModel
    let imagePipeline: any ImagePipeline
    @Bindable var engagementStore: EngagementStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProfileSectionContainerChrome(
            section: .clips,
            state: viewModel.state,
            onRetry: { Task { await viewModel.refresh() } }
        ) {
            LazyVStack(spacing: ExperienceSpacing.sm) {
                ForEach(viewModel.items) { reel in
                    ProfileClipCard(
                        reel: reel,
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        onOpen: { viewModel.openClip(reel) }
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
                }
            }
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: viewModel.items.map(\.id)
            )
            .onChange(of: viewModel.items.map(\.id)) { _, ids in
                viewModel.prefetchEngagement(for: ids)
            }
            .onAppear {
                viewModel.prefetchEngagement(for: viewModel.items.map(\.id))
            }
            .accessibilityIdentifier("profile.clips.list")
        }
    }
}
