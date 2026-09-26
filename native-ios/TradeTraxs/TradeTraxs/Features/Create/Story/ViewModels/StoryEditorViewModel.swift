import Foundation
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class StoryEditorViewModel {
    let sourceImage: UIImage
    private(set) var canvas = StoryCanvasState()
    private(set) var canvasSize: CGSize = .zero
    private(set) var isEditingText = false
    private(set) var draftText = ""
    private(set) var selectedTextFill: StoryTextFill = .fromPreset(.white)
    private(set) var selectedAlignment: TextAlignment = .center
    private(set) var showsTextBackground = false

    init(sourceImage: UIImage) {
        self.sourceImage = sourceImage
    }

    var selectedOverlay: StoryTextOverlay? {
        guard let id = canvas.selectedTextID else { return nil }
        return canvas.textOverlays.first { $0.id == id }
    }

    func updateCanvasSize(_ size: CGSize) {
        canvasSize = size
    }

    func selectText(_ id: UUID?) {
        canvas.selectedTextID = id
        if let id, let overlay = canvas.textOverlays.first(where: { $0.id == id }) {
            draftText = overlay.text
            selectedTextFill = overlay.textFill
            selectedAlignment = overlay.alignment
            showsTextBackground = overlay.showsBackground
        }
    }

    func beginAddingText() {
        let overlay = StoryTextOverlay(text: "", normalizedCenter: CGPoint(x: 0.5, y: 0.45))
        canvas.textOverlays.append(overlay)
        canvas.selectedTextID = overlay.id
        draftText = ""
        selectedTextFill = .fromPreset(.white)
        selectedAlignment = .center
        showsTextBackground = false
        isEditingText = true
    }

    func beginEditingSelectedText() {
        guard canvas.selectedTextID != nil else { return }
        isEditingText = true
    }

    func updateDraftText(_ text: String) {
        draftText = text
        applyDraftToSelectedOverlay()
    }

    func setSelectedColor(_ color: StoryTextColor) {
        selectedTextFill = .fromPreset(color)
        applyDraftToSelectedOverlay()
    }

    func setCustomTextColor(_ color: Color) {
        selectedTextFill = StoryTextFill.fromSwiftUIColor(color)
        applyDraftToSelectedOverlay()
    }

    func setSelectedAlignment(_ alignment: TextAlignment) {
        selectedAlignment = alignment
        applyDraftToSelectedOverlay()
    }

    func setShowsTextBackground(_ value: Bool) {
        showsTextBackground = value
        applyDraftToSelectedOverlay()
    }

    func finishEditingText() {
        if let id = canvas.selectedTextID,
           let index = canvas.textOverlays.firstIndex(where: { $0.id == id }),
           canvas.textOverlays[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            canvas.textOverlays.remove(at: index)
            canvas.selectedTextID = nil
        }
        isEditingText = false
    }

    func deleteSelectedText() {
        guard let id = canvas.selectedTextID else { return }
        deleteOverlay(id: id)
    }

    func deleteOverlay(id: UUID) {
        canvas.textOverlays.removeAll { $0.id == id }
        if canvas.selectedTextID == id {
            canvas.selectedTextID = nil
            isEditingText = false
            draftText = ""
        }
    }

    func updateImageScale(_ scale: CGFloat) {
        canvas.imageScale = min(max(scale, 0.15), 4)
    }

    func updateImageOffset(_ offset: CGSize) {
        canvas.imageOffset = offset
    }

    func updateOverlayPosition(id: UUID, normalizedCenter: CGPoint) {
        guard let index = canvas.textOverlays.firstIndex(where: { $0.id == id }) else { return }
        canvas.textOverlays[index].normalizedCenter = normalizedCenter
    }

    func updateOverlayScale(id: UUID, scale: CGFloat) {
        guard let index = canvas.textOverlays.firstIndex(where: { $0.id == id }) else { return }
        canvas.textOverlays[index].scale = min(max(scale, 0.5), 3)
    }

    func updateOverlayRotation(id: UUID, radians: CGFloat) {
        guard let index = canvas.textOverlays.firstIndex(where: { $0.id == id }) else { return }
        canvas.textOverlays[index].rotationRadians = radians
    }

    func renderFinalImage() -> UIImage? {
        StoryImageRenderer.render(
            sourceImage: sourceImage,
            canvas: canvas,
            canvasSize: canvasSize
        )
    }

    private func applyDraftToSelectedOverlay() {
        guard let id = canvas.selectedTextID,
              let index = canvas.textOverlays.firstIndex(where: { $0.id == id })
        else { return }
        canvas.textOverlays[index].text = draftText
        canvas.textOverlays[index].textFill = selectedTextFill
        canvas.textOverlays[index].alignment = selectedAlignment
        canvas.textOverlays[index].showsBackground = showsTextBackground
    }
}
