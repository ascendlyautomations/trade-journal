import CoreGraphics

/// Story editor and viewer share a 9:16 composer canvas inside arbitrary containers.
enum StoryComposerGeometry {
  /// Largest 9:16 rect that fits inside `container` (aspect fit), centered.
  static func aspectFitStoryCanvas(in container: CGSize) -> CGRect {
    guard container.width > 0, container.height > 0 else {
      return CGRect(origin: .zero, size: container)
    }

    let targetAspect = StoryCanvasState.canvasAspectRatio
    let containerAspect = container.width / container.height

    let size: CGSize
    if containerAspect > targetAspect {
      let height = container.height
      size = CGSize(width: height * targetAspect, height: height)
    } else {
      let width = container.width
      size = CGSize(width: width, height: width / targetAspect)
    }

    return CGRect(
      x: (container.width - size.width) / 2,
      y: (container.height - size.height) / 2,
      width: size.width,
      height: size.height
    )
  }
}