import CoreGraphics
import Foundation
import UIKit

// MARK: - Normalized crop (orientation-normalized source image, 0…1)

/// Visible region in the orientation-normalized source image bitmap.
nonisolated struct NormalizedImageCrop: Equatable, Hashable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let full = NormalizedImageCrop(x: 0, y: 0, width: 1, height: 1)
}

extension NormalizedImageCrop: Codable {
    enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try Self.decodeCGFloat(from: container, forKey: .x)
        y = try Self.decodeCGFloat(from: container, forKey: .y)
        width = try Self.decodeCGFloat(from: container, forKey: .width)
        height = try Self.decodeCGFloat(from: container, forKey: .height)
    }

    private static func decodeCGFloat(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> CGFloat {
        if let value = try? container.decode(Double.self, forKey: key) {
            return CGFloat(value)
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return CGFloat(value)
        }
        // Legacy wire bug stored 0/1 crop coords as JSON booleans.
        if let value = try? container.decode(Bool.self, forKey: key) {
            return value ? 1 : 0
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected numeric crop coordinate"
        )
    }
}

// MARK: - Authoritative presentation model

/// Single source of truth for Posts / Trades / Achievements Feed + Profile rendering.
nonisolated struct ContentImagePresentation: Equatable, Hashable, Codable, Sendable {
    /// Viewport width / height (e.g. 0.8 for 4:5 portrait cap).
    var presentationAspectRatio: CGFloat
    /// When set, aspect-fill this region into the viewport. `nil` = show full image (natural aspect).
    var normalizedCrop: NormalizedImageCrop?
    /// Author framing preset at upload (`original`, `square`, …).
    var aspectMode: ImageCropAspectOption
    var sourceWidth: Int?
    var sourceHeight: Int?

    var usesFillCrop: Bool { requiresFramedViewport }

    /// True when the saved presentation should aspect-fill into a fixed viewport (not show full image fit).
    var requiresFramedViewport: Bool {
        if normalizedCrop != nil { return true }
        switch aspectMode {
        case .square, .portrait, .landscape:
            return true
        case .original:
            if let w = sourceWidth, let h = sourceHeight, h > 0 {
                let imageAspect = CGFloat(w) / CGFloat(h)
                return FeedMediaLayout.exceedsFeedPortraitLimit(imageAspect: imageAspect)
            }
            return false
        }
    }

    /// Crop rect used for rendering — falls back to a centered crop when metadata is partial.
    func resolvedCrop(imagePixelSize: CGSize) -> NormalizedImageCrop? {
        if let normalizedCrop { return normalizedCrop }
        guard requiresFramedViewport else { return nil }
        let imageAspect = max(imagePixelSize.width / max(imagePixelSize.height, 1), 0.01)
        return Self.centerCrop(
            imageAspect: imageAspect,
            presentationAspect: presentationAspectRatio
        )
    }

    static func centerCrop(imageAspect: CGFloat, presentationAspect: CGFloat) -> NormalizedImageCrop {
        let safeImageAspect = max(imageAspect, 0.01)
        let safePresentationAspect = max(presentationAspect, 0.01)
        if safeImageAspect > safePresentationAspect {
            let width = safePresentationAspect / safeImageAspect
            return NormalizedImageCrop(
                x: max(0, (1 - width) / 2),
                y: 0,
                width: width,
                height: 1
            )
        }
        let height = safeImageAspect / safePresentationAspect
        return NormalizedImageCrop(
            x: 0,
            y: max(0, (1 - height) / 2),
            width: 1,
            height: height
        )
    }

    enum CodingKeys: String, CodingKey {
        case presentationAspectRatio = "presentation_aspect_ratio"
        case normalizedCrop = "normalized_crop"
        case aspectMode = "aspect_mode"
        case sourceWidth = "source_width"
        case sourceHeight = "source_height"
    }

    init(
        presentationAspectRatio: CGFloat,
        normalizedCrop: NormalizedImageCrop?,
        aspectMode: ImageCropAspectOption,
        sourceWidth: Int? = nil,
        sourceHeight: Int? = nil
    ) {
        self.presentationAspectRatio = presentationAspectRatio
        self.normalizedCrop = normalizedCrop
        self.aspectMode = aspectMode
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presentationAspectRatio = try container.decode(CGFloat.self, forKey: .presentationAspectRatio)
        normalizedCrop = try container.decodeIfPresent(NormalizedImageCrop.self, forKey: .normalizedCrop)
        let rawMode = try container.decodeIfPresent(String.self, forKey: .aspectMode)
        aspectMode = rawMode.flatMap { ImageCropAspectOption(rawValue: $0) } ?? .original
        sourceWidth = try container.decodeIfPresent(Int.self, forKey: .sourceWidth)
        sourceHeight = try container.decodeIfPresent(Int.self, forKey: .sourceHeight)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presentationAspectRatio, forKey: .presentationAspectRatio)
        try container.encodeIfPresent(normalizedCrop, forKey: .normalizedCrop)
        try container.encode(aspectMode.rawValue, forKey: .aspectMode)
        try container.encodeIfPresent(sourceWidth, forKey: .sourceWidth)
        try container.encodeIfPresent(sourceHeight, forKey: .sourceHeight)
    }
}

// MARK: - Factory

extension ContentImagePresentation {
    static func make(
        aspectOption: ImageCropAspectOption,
        imagePixelSize: CGSize,
        viewportSize: CGSize,
        transform: ImageCropTransform
    ) -> ContentImagePresentation {
        let imageAspect = max(imagePixelSize.width / max(imagePixelSize.height, 1), 0.01)
        let presentationAspect = FeedMediaLayout.presentationAspect(
            imageAspect: imageAspect,
            aspectOption: aspectOption
        )
        let requiresFill = FeedMediaLayout.requiresFillCrop(
            imageAspect: imageAspect,
            aspectOption: aspectOption
        )

        let crop: NormalizedImageCrop?
        if requiresFill, viewportSize.width > 0, viewportSize.height > 0 {
            crop = Self.normalizedCropFromEditor(
                imagePixelSize: imagePixelSize,
                viewportSize: viewportSize,
                transform: transform
            )
        } else {
            crop = nil
        }

        let sourceW = Int(imagePixelSize.width.rounded())
        let sourceH = Int(imagePixelSize.height.rounded())

        #if DEBUG
        ImagePipelineProbe.log(
            sourcePixels: imagePixelSize,
            normalizedPixels: imagePixelSize,
            sourceAspectRatio: imageAspect,
            selectedMode: aspectOption.rawValue,
            presentationAspectRatio: presentationAspect,
            cropRect: crop,
            focalPoint: nil
        )
        CropPipelineProbe.logSaved(
            selectedMode: aspectOption.rawValue,
            presentationAspectRatio: presentationAspect,
            normalizedCropRect: crop,
            zoom: transform.zoom,
            offset: transform.offset
        )
        #endif

        return ContentImagePresentation(
            presentationAspectRatio: presentationAspect,
            normalizedCrop: crop,
            aspectMode: aspectOption,
            sourceWidth: sourceW,
            sourceHeight: sourceH
        )
    }

    /// Backward-compatible helper — derives editor viewport from container width.
    static func make(
        aspectOption: ImageCropAspectOption,
        imagePixelSize: CGSize,
        containerWidth: CGFloat,
        transform: ImageCropTransform
    ) -> ContentImagePresentation {
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: containerWidth,
            imagePixelSize: imagePixelSize,
            aspectOption: aspectOption
        )
        return make(
            aspectOption: aspectOption,
            imagePixelSize: imagePixelSize,
            viewportSize: viewport,
            transform: transform
        )
    }

    /// Feed card — show the full decoded bitmap at its natural aspect (no display-time crop).
    static func naturalFit(imageAspect: CGFloat) -> ContentImagePresentation {
        ContentImagePresentation(
            presentationAspectRatio: max(imageAspect, 0.01),
            normalizedCrop: nil,
            aspectMode: .original
        )
    }

    /// Stored presentation from a media reference or local cache.
    static func storedPresentation(for reference: MediaReference?) -> ContentImagePresentation? {
        guard let reference else { return nil }
        if let fromReference = reference.imagePresentation { return fromReference }
        return ContentImagePresentationStore.presentation(forMediaURL: reference.id)
    }

    /// Legacy metadata-only rows that require display-time crop via an explicit normalized rect.
    static func explicitLegacyCrop(from stored: ContentImagePresentation?) -> ContentImagePresentation? {
        guard let stored, stored.normalizedCrop != nil else { return nil }
        return stored
    }

    /// Legacy rows without stored metadata — centered 4:5 fallback only when taller than 4:5.
    static func inferredLegacy(imageAspect: CGFloat) -> ContentImagePresentation {
        let safeAspect = max(imageAspect, 0.01)
        if FeedMediaLayout.exceedsFeedPortraitLimit(imageAspect: safeAspect) {
            let presentationAspect = FeedMediaLayout.minimumFeedAspectRatio
            let nh = min(1, presentationAspect / safeAspect)
            let ny = max(0, (1 - nh) / 2)
            return ContentImagePresentation(
                presentationAspectRatio: presentationAspect,
                normalizedCrop: NormalizedImageCrop(x: 0, y: ny, width: 1, height: nh),
                aspectMode: .original
            )
        }
        return naturalFit(imageAspect: safeAspect)
    }

    static func normalizedCropFromEditor(
        imagePixelSize: CGSize,
        viewportSize: CGSize,
        transform: ImageCropTransform
    ) -> NormalizedImageCrop {
        let draw = ImageCropMath.computeDrawRect(
            imageWidth: imagePixelSize.width,
            imageHeight: imagePixelSize.height,
            frameWidth: viewportSize.width,
            frameHeight: viewportSize.height,
            zoom: transform.zoom,
            offset: transform.offset
        )

        let w = max(imagePixelSize.width, 1)
        let h = max(imagePixelSize.height, 1)
        let fw = viewportSize.width
        let fh = viewportSize.height

        guard draw.width > 0, draw.height > 0 else { return .full }

        let ix0 = max(0, (0 - draw.x) / draw.width * w)
        let iy0 = max(0, (0 - draw.y) / draw.height * h)
        let ix1 = min(w, (fw - draw.x) / draw.width * w)
        let iy1 = min(h, (fh - draw.y) / draw.height * h)

        return NormalizedImageCrop(
            x: ix0 / w,
            y: iy0 / h,
            width: max(0, min(1, (ix1 - ix0) / w)),
            height: max(0, min(1, (iy1 - iy0) / h))
        )
    }

    /// Migrate v1 UserDefaults entries (zoom/offset) into normalized crop.
    static func migrated(fromLegacy legacy: LegacyFeedMediaPresentationV1) -> ContentImagePresentation {
        let imageAspect = legacy.sourceAspectRatio ?? FeedMediaLayout.minimumFeedAspectRatio
        let presentationAspect = FeedMediaLayout.presentationAspect(
            imageAspect: imageAspect,
            aspectOption: legacy.aspectOption
        )
        guard legacy.usesFillCrop,
              let w = legacy.sourceWidth,
              let h = legacy.sourceHeight,
              w > 0, h > 0
        else {
            return ContentImagePresentation(
                presentationAspectRatio: presentationAspect,
                normalizedCrop: nil,
                aspectMode: legacy.aspectOption,
                sourceWidth: legacy.sourceWidth,
                sourceHeight: legacy.sourceHeight
            )
        }
        let pixelSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        let viewport = FeedMediaLayout.editorViewportSize(
            containerWidth: 390,
            imagePixelSize: pixelSize,
            aspectOption: legacy.aspectOption
        )
        let crop = normalizedCropFromEditor(
            imagePixelSize: pixelSize,
            viewportSize: viewport,
            transform: legacy.transform
        )
        return ContentImagePresentation(
            presentationAspectRatio: presentationAspect,
            normalizedCrop: crop,
            aspectMode: legacy.aspectOption,
            sourceWidth: w,
            sourceHeight: h
        )
    }
}

/// Decoding shim for pre-normalized UserDefaults payloads.
nonisolated struct LegacyFeedMediaPresentationV1: Decodable {
    var aspectOption: ImageCropAspectOption
    var transform: ImageCropTransform
    var usesFillCrop: Bool
    var sourceWidth: Int?
    var sourceHeight: Int?
    var sourceAspectRatio: CGFloat?

    enum CodingKeys: String, CodingKey {
        case aspectOption, transform, usesFillCrop, sourceWidth, sourceHeight, sourceAspectRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawAspect = try container.decode(String.self, forKey: .aspectOption)
        aspectOption = ImageCropAspectOption(rawValue: rawAspect) ?? .original
        transform = try container.decode(ImageCropTransform.self, forKey: .transform)
        usesFillCrop = try container.decode(Bool.self, forKey: .usesFillCrop)
        sourceWidth = try container.decodeIfPresent(Int.self, forKey: .sourceWidth)
        sourceHeight = try container.decodeIfPresent(Int.self, forKey: .sourceHeight)
        sourceAspectRatio = try container.decodeIfPresent(CGFloat.self, forKey: .sourceAspectRatio)
    }
}

typealias FeedMediaPresentation = ContentImagePresentation

/// Result from the shared crop editor — `image` contains the physically cropped pixels.
nonisolated struct ImageCropSelectionResult: Sendable {
    let image: UIImage
    let aspectMode: ImageCropAspectOption
    let sourcePixelSize: CGSize
}

// MARK: - Layout + draw

extension ContentImagePresentation {
    nonisolated static func drawRect(
        imagePixelSize: CGSize,
        containerSize: CGSize,
        presentation: ContentImagePresentation
    ) -> ImageCropMath.DrawRect? {
        guard presentation.requiresFramedViewport,
              let crop = presentation.resolvedCrop(imagePixelSize: imagePixelSize),
              containerSize.width > 0,
              containerSize.height > 0
        else { return nil }

        let w = imagePixelSize.width
        let h = imagePixelSize.height
        let px = crop.x * w
        let py = crop.y * h
        let pw = max(crop.width * w, 1)
        let ph = max(crop.height * h, 1)

        let fw = containerSize.width
        let fh = containerSize.height
        let scale = max(fw / pw, fh / ph)
        let displayW = w * scale
        let displayH = h * scale
        let x = -px * scale
        let y = -py * scale

        return ImageCropMath.DrawRect(x: x, y: y, width: displayW, height: displayH)
    }
}

extension ContentImagePresentation {
    nonisolated static func mediaReference(
        url: String?,
        crop: ContentImagePresentation?
    ) -> MediaReference? {
        guard let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return MediaReference(
            id: trimmed,
            kind: .image,
            altText: nil,
            imagePresentation: crop
        )
    }
}

// MARK: - Persistence cache (post-upload until bootstrap returns authoritative row)

@MainActor
enum ContentImagePresentationStore {
    private static let defaultsKey = "ContentImagePresentationStore.v2"
    private static let legacyDefaultsKey = "FeedMediaPresentationStore.v1"
    private static var memory: [String: ContentImagePresentation] = [:]
    private static var didLoad = false

    static func save(_ presentation: ContentImagePresentation, forMediaURL url: String) {
        loadIfNeeded()
        let key = normalizedKey(url)
        guard !key.isEmpty else { return }
        memory[key] = presentation
        persist()
    }

    static func presentation(forMediaURL url: String) -> ContentImagePresentation? {
        loadIfNeeded()
        return memory[normalizedKey(url)]
    }

    private static func normalizedKey(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: ContentImagePresentation].self, from: data) {
            memory = decoded
            return
        }
        guard let legacyData = UserDefaults.standard.data(forKey: legacyDefaultsKey),
              let legacy = try? JSONDecoder().decode([String: LegacyFeedMediaPresentationV1].self, from: legacyData)
        else { return }
        memory = legacy.mapValues { ContentImagePresentation.migrated(fromLegacy: $0) }
    }

    private static func persist() {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

typealias FeedMediaPresentationStore = ContentImagePresentationStore

extension ImageCropTransform: Codable {
    enum CodingKeys: String, CodingKey {
        case zoom
        case offsetX
        case offsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        zoom = try container.decode(CGFloat.self, forKey: .zoom)
        let x = try container.decode(CGFloat.self, forKey: .offsetX)
        let y = try container.decode(CGFloat.self, forKey: .offsetY)
        offset = CGSize(width: x, height: y)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(zoom, forKey: .zoom)
        try container.encode(offset.width, forKey: .offsetX)
        try container.encode(offset.height, forKey: .offsetY)
    }
}

// MARK: - JSON helpers (Feed bootstrap / REST)

nonisolated enum ContentImagePresentationCodec {
    static func decode(from value: JSONValue?) -> ContentImagePresentation? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(ContentImagePresentation.self, from: data)
    }

    static func decodeJSONData(_ data: Data) -> ContentImagePresentation? {
        try? JSONDecoder().decode(ContentImagePresentation.self, from: data)
    }

    /// Encodes crop metadata for PostgREST `jsonb` columns.
    static func encodeJSONValue(_ presentation: ContentImagePresentation?) -> JSONValue? {
        guard let presentation else { return nil }
        guard let data = try? JSONEncoder().encode(presentation) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// True when Supabase/PostgREST rejects `image_crop` because the column is absent.
    static func isMissingImageCropColumnError(_ error: Error) -> Bool {
        let haystack = errorDiagnosticText(error).lowercased()
        guard haystack.contains("image_crop") else { return false }
        return haystack.contains("pgrst204")
            || haystack.contains("could not find")
            || haystack.contains("schema cache")
            || haystack.contains("42703")
            || haystack.contains("does not exist")
    }

    private static func errorDiagnosticText(_ error: Error) -> String {
        var parts = [String(describing: error)]
        if let app = error as? AppError, case .transport(let network) = app {
            parts.append(String(describing: network))
            switch network {
            case .server(_, let message):
                if let message { parts.append(message) }
            case .validation(_, let message):
                parts.append(message)
            default:
                break
            }
        }
        if let localized = (error as? LocalizedError)?.errorDescription {
            parts.append(localized)
        }
        return parts.joined(separator: " ")
    }

    private static func jsonValue(from value: Any) -> JSONValue {
        switch value {
        case let string as String:
            return .string(string)
        // NSNumber must precede Bool — NSNumber(0/1) otherwise casts to false/true.
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .number(Double(int))
        case let double as Double:
            return .number(double)
        case let float as Float:
            return .number(Double(float))
        case let dictionary as [String: Any]:
            return .object(dictionary.mapValues { jsonValue(from: $0) })
        case let array as [Any]:
            return .array(array.map { jsonValue(from: $0) })
        default:
            return .null
        }
    }
}

/// Insert body for `profile_posts` — omits `image_crop` when the column is not deployed yet.
nonisolated struct ProfileWallPostInsertBody: Encodable, Sendable {
    var user_id: String
    var content: String
    var image_url: String?
    var image_crop: JSONValue?
    var includeImageCropKey: Bool

    enum CodingKeys: String, CodingKey {
        case user_id, content, image_url, image_crop
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(image_url, forKey: .image_url)
        if includeImageCropKey {
            try container.encodeIfPresent(image_crop, forKey: .image_crop)
        }
    }
}

/// Insert body for `achievements` — omits `image_crop` when the column is not deployed yet.
nonisolated struct AchievementInsertBody: Encodable, Sendable {
    var user_id: String
    var achievement_type: String
    var title: String
    var description: String?
    var badge_key: String
    var category: String
    var value_numeric: Double?
    var value_text: String?
    var currency: String?
    var account_id: String?
    var firm: String?
    var image_url: String?
    var image_crop: JSONValue?
    var achieved_at: String
    var is_public: Bool
    var is_featured: Bool
    var includeImageCropKey: Bool

    enum CodingKeys: String, CodingKey {
        case user_id, achievement_type, title, description, badge_key, category
        case value_numeric, value_text, currency, account_id, firm
        case image_url, image_crop, achieved_at, is_public, is_featured
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(achievement_type, forKey: .achievement_type)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(badge_key, forKey: .badge_key)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(value_numeric, forKey: .value_numeric)
        try container.encodeIfPresent(value_text, forKey: .value_text)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(account_id, forKey: .account_id)
        try container.encodeIfPresent(firm, forKey: .firm)
        try container.encodeIfPresent(image_url, forKey: .image_url)
        if includeImageCropKey {
            try container.encodeIfPresent(image_crop, forKey: .image_crop)
        }
        try container.encode(achieved_at, forKey: .achieved_at)
        try container.encode(is_public, forKey: .is_public)
        try container.encode(is_featured, forKey: .is_featured)
    }
}

// MARK: - DEBUG probes

#if DEBUG
enum CropPipelineProbe {
    static func log(_ message: String) {
        print("[CropPipeline] \(message)")
    }

    static func logSaved(
        selectedMode: String,
        presentationAspectRatio: CGFloat,
        normalizedCropRect: NormalizedImageCrop?,
        zoom: CGFloat,
        offset: CGSize
    ) {
        log("selectedMode=\(selectedMode)")
        log("selectedAspectRatio=\(String(format: "%.4f", presentationAspectRatio))")
        log("normalizedCropRect=\(cropText(normalizedCropRect))")
        log("zoom=\(String(format: "%.3f", zoom))")
        log("offset=(\(Int(offset.width)),\(Int(offset.height)))")
        log("savedPresentationAspectRatio=\(String(format: "%.4f", presentationAspectRatio))")
    }

    private static func cropText(_ crop: NormalizedImageCrop?) -> String {
        guard let crop else { return "nil" }
        return String(
            format: "x=%.3f y=%.3f w=%.3f h=%.3f",
            crop.x, crop.y, crop.width, crop.height
        )
    }
}

enum CropRenderProbe {
    static func log(
        surface: String,
        selectedMode: String,
        presentationAspectRatio: CGFloat,
        cropRect: NormalizedImageCrop?,
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) {
        let cropText: String
        if let cropRect {
            cropText = String(
                format: "x=%.3f y=%.3f w=%.3f h=%.3f",
                cropRect.x, cropRect.y, cropRect.width, cropRect.height
            )
        } else {
            cropText = "nil"
        }
        print("[CropRender] surface=\(surface) selectedMode=\(selectedMode) "
            + "presentationAspectRatio=\(String(format: "%.4f", presentationAspectRatio)) "
            + "cropRect=\(cropText) "
            + "containerWidth=\(String(format: "%.1f", containerWidth)) "
            + "containerHeight=\(String(format: "%.1f", containerHeight))")
    }
}

enum ImagePipelineProbe {
    static func log(
        sourcePixels: CGSize,
        normalizedPixels: CGSize,
        sourceAspectRatio: CGFloat,
        selectedMode: String,
        presentationAspectRatio: CGFloat,
        cropRect: NormalizedImageCrop?,
        focalPoint: CGPoint?
    ) {
        let cropText: String
        if let cropRect {
            cropText = String(
                format: "x=%.3f y=%.3f w=%.3f h=%.3f",
                cropRect.x, cropRect.y, cropRect.width, cropRect.height
            )
        } else {
            cropText = "nil"
        }
        let focalText = focalPoint.map { "(\(String(format: "%.3f", $0.x)),\(String(format: "%.3f", $0.y)))" } ?? "nil"
        print(
            "[ImagePipeline] sourcePixels=\(Int(sourcePixels.width))x\(Int(sourcePixels.height)) "
                + "normalizedPixels=\(Int(normalizedPixels.width))x\(Int(normalizedPixels.height)) "
                + "sourceAspectRatio=\(String(format: "%.4f", sourceAspectRatio)) "
                + "selectedMode=\(selectedMode) "
                + "presentationAspectRatio=\(String(format: "%.4f", presentationAspectRatio)) "
                + "cropRect=\(cropText) focalPoint=\(focalText)"
        )
    }
}

enum FeedImageRenderProbe {
    static func log(
        mediaID: String,
        surface: String,
        decodedPixels: CGSize,
        containerSize: CGSize,
        contentMode: String,
        imageViewFrame: CGRect?,
        layoutMode: String
    ) {
        let decodedAspect = decodedPixels.width / max(decodedPixels.height, 1)
        let containerAspect = containerSize.width / max(containerSize.height, 1)
        let frameText: String
        if let imageViewFrame {
            frameText = String(
                format: "(%.1f,%.1f,%.1fx%.1f)",
                imageViewFrame.origin.x,
                imageViewFrame.origin.y,
                imageViewFrame.width,
                imageViewFrame.height
            )
        } else {
            frameText = "pending"
        }
        print(
            "[FEED_IMAGE_RENDER] mediaID=\(mediaID) surface=\(surface) "
                + "decoded=\(Int(decodedPixels.width))x\(Int(decodedPixels.height)) "
                + "container=\(Int(containerSize.width))x\(Int(containerSize.height)) "
                + "decodedAspect=\(String(format: "%.4f", decodedAspect)) "
                + "containerAspect=\(String(format: "%.4f", containerAspect)) "
                + "contentMode=\(contentMode) layoutMode=\(layoutMode) imageViewFrame=\(frameText)"
        )
    }
}

enum FeedImageDisplayProbe {
    static func log(
        mediaID: String,
        decodedAspect: CGFloat,
        containerWidth: CGFloat,
        storedHadCropRect: Bool,
        presentation: ContentImagePresentation,
        usesDetailLikeLayout: Bool
    ) {
        let cropText: String
        if let crop = presentation.normalizedCrop {
            cropText = String(
                format: "x=%.3f y=%.3f w=%.3f h=%.3f",
                crop.x, crop.y, crop.width, crop.height
            )
        } else {
            cropText = "nil"
        }
        let containerHeight = usesDetailLikeLayout
            ? max(containerWidth / max(decodedAspect, 0.01), FeedMediaLayout.minHeight)
            : max(containerWidth / max(presentation.presentationAspectRatio, 0.01), FeedMediaLayout.minHeight)
        print(
            "[FeedImageDisplay] mediaID=\(mediaID) "
                + "decodedAspect=\(String(format: "%.4f", decodedAspect)) "
                + "detailLikeLayout=\(usesDetailLikeLayout) "
                + "storedHadCropRect=\(storedHadCropRect) "
                + "cropRect=\(cropText) "
                + "container=\(Int(containerWidth))x\(Int(containerHeight))"
        )
    }
}

enum ImageRenderProbe {
    static func log(
        surface: String,
        availableWidth: CGFloat,
        presentationAspectRatio: CGFloat,
        calculatedHeight: CGFloat,
        cropRect: NormalizedImageCrop?,
        mediaID: String
    ) {
        let cropText: String
        if let cropRect {
            cropText = String(
                format: "x=%.3f y=%.3f w=%.3f h=%.3f",
                cropRect.x, cropRect.y, cropRect.width, cropRect.height
            )
        } else {
            cropText = "nil"
        }
        print(
            "[ImageRender] surface=\(surface) availableWidth=\(String(format: "%.1f", availableWidth)) "
                + "presentationAspectRatio=\(String(format: "%.4f", presentationAspectRatio)) "
                + "calculatedHeight=\(String(format: "%.1f", calculatedHeight)) "
                + "cropRect=\(cropText) mediaID=\(mediaID)"
        )
    }
}
#else
enum CropPipelineProbe {
    static func log(_ message: String) {}
    static func logSaved(
        selectedMode: String,
        presentationAspectRatio: CGFloat,
        normalizedCropRect: NormalizedImageCrop?,
        zoom: CGFloat,
        offset: CGSize
    ) {}
}
enum CropRenderProbe {
    static func log(
        surface: String,
        selectedMode: String,
        presentationAspectRatio: CGFloat,
        cropRect: NormalizedImageCrop?,
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) {}
}
enum ImagePipelineProbe {
    static func log(
        sourcePixels: CGSize,
        normalizedPixels: CGSize,
        sourceAspectRatio: CGFloat,
        selectedMode: String,
        presentationAspectRatio: CGFloat,
        cropRect: NormalizedImageCrop?,
        focalPoint: CGPoint?
    ) {}
}
enum FeedImageRenderProbe {
    static func log(
        mediaID: String,
        surface: String,
        decodedPixels: CGSize,
        containerSize: CGSize,
        contentMode: String,
        imageViewFrame: CGRect?,
        layoutMode: String
    ) {}
}
enum FeedImageDisplayProbe {
    static func log(
        mediaID: String,
        decodedAspect: CGFloat,
        containerWidth: CGFloat,
        storedHadCropRect: Bool,
        presentation: ContentImagePresentation,
        usesDetailLikeLayout: Bool
    ) {}
}
enum ImageRenderProbe {
    static func log(
        surface: String,
        availableWidth: CGFloat,
        presentationAspectRatio: CGFloat,
        calculatedHeight: CGFloat,
        cropRect: NormalizedImageCrop?,
        mediaID: String
    ) {}
}
#endif
