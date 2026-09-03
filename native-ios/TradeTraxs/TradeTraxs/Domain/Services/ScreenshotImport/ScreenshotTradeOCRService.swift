import CoreGraphics
import Foundation
import Vision

/// On-device Apple Vision text recognition for trade-history screenshots.
nonisolated enum ScreenshotTradeOCRService {
    enum OCRFailure: Error, LocalizedError {
        case noText
        case imageUnavailable

        var errorDescription: String? {
            switch self {
            case .noText: return "No readable text found in screenshot."
            case .imageUnavailable: return "Couldn't read screenshot image."
            }
        }
    }

    static func recognizeText(in cgImage: CGImage) async throws -> [OCRTextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(throwing: OCRFailure.noText)
                    return
                }
                let blocks = observations.enumerated().compactMap { index, observation -> OCRTextBlock? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return OCRTextBlock(
                        id: "ocr-\(index)",
                        text: trimmed,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence
                    )
                }
                if blocks.isEmpty {
                    continuation.resume(throwing: OCRFailure.noText)
                } else {
                    continuation.resume(returning: blocks)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.008

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func recognizeText(in images: [CGImage]) async throws -> [[OCRTextBlock]] {
        var results: [[OCRTextBlock]] = []
        results.reserveCapacity(images.count)
        for image in images {
            do {
                let blocks = try await recognizeText(in: image)
                results.append(blocks)
            } catch OCRFailure.noText {
                results.append([])
            }
        }
        if results.allSatisfy(\.isEmpty) {
            throw OCRFailure.noText
        }
        return results
    }
}
