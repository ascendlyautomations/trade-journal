"use client"

import { useCallback, useMemo, useState } from "react"
import {
  clampOverlayScale,
  createEmptyStoryCanvasState,
  createStoryTextOverlay,
  publishableTextOverlays,
  storyTextFillFromPreset,
  type StoryCanvasState,
  type StoryTextAlignment,
  type StoryTextColorPreset,
  type StoryTextFill,
  type StoryTextOverlay,
} from "./storyTextOverlay"

export function useStoryEditorState(initialCanvas?: StoryCanvasState) {
  const [canvas, setCanvas] = useState<StoryCanvasState>(
    initialCanvas ?? createEmptyStoryCanvasState()
  )
  const [canvasSize, setCanvasSize] = useState({ width: 0, height: 0 })
  const [isEditingText, setIsEditingText] = useState(false)
  const [draftText, setDraftText] = useState("")
  const [selectedTextFill, setSelectedTextFill] = useState<StoryTextFill>(
    storyTextFillFromPreset("white")
  )
  const [selectedAlignment, setSelectedAlignment] =
    useState<StoryTextAlignment>("center")
  const [showsTextBackground, setShowsTextBackground] = useState(false)

  const selectedOverlay = useMemo(() => {
    if (!canvas.selectedTextID) return null
    return canvas.textOverlays.find((o) => o.id === canvas.selectedTextID) ?? null
  }, [canvas.selectedTextID, canvas.textOverlays])

  const applyDraftToSelected = useCallback(
    (
      patch: Partial<
        Pick<
          StoryTextOverlay,
          "text" | "textFill" | "alignment" | "showsBackground"
        >
      >
    ) => {
      setCanvas((prev) => {
        const id = prev.selectedTextID
        if (!id) return prev
        const index = prev.textOverlays.findIndex((o) => o.id === id)
        if (index < 0) return prev
        const next = [...prev.textOverlays]
        next[index] = { ...next[index], ...patch }
        return { ...prev, textOverlays: next }
      })
    },
    []
  )

  const selectText = useCallback((id: string | null) => {
    setCanvas((prev) => {
      if (id === prev.selectedTextID) return prev
      const overlay = id
        ? prev.textOverlays.find((o) => o.id === id)
        : undefined
      if (overlay) {
        setDraftText(overlay.text)
        setSelectedTextFill(overlay.textFill)
        setSelectedAlignment(overlay.alignment)
        setShowsTextBackground(overlay.showsBackground)
      }
      return { ...prev, selectedTextID: id }
    })
  }, [])

  const beginAddingText = useCallback(() => {
    const overlay = createStoryTextOverlay()
    setCanvas((prev) => ({
      ...prev,
      textOverlays: [...prev.textOverlays, overlay],
      selectedTextID: overlay.id,
    }))
    setDraftText("")
    setSelectedTextFill(storyTextFillFromPreset("white"))
    setSelectedAlignment("center")
    setShowsTextBackground(false)
    setIsEditingText(true)
  }, [])

  const beginEditingSelectedText = useCallback(() => {
    if (!canvas.selectedTextID) return
    const overlay = canvas.textOverlays.find((o) => o.id === canvas.selectedTextID)
    if (overlay) {
      setDraftText(overlay.text)
      setSelectedTextFill(overlay.textFill)
      setSelectedAlignment(overlay.alignment)
      setShowsTextBackground(overlay.showsBackground)
    }
    setIsEditingText(true)
  }, [canvas.selectedTextID, canvas.textOverlays])

  const updateDraftText = useCallback(
    (text: string) => {
      setDraftText(text)
      applyDraftToSelected({ text })
    },
    [applyDraftToSelected]
  )

  const setSelectedColor = useCallback(
    (preset: StoryTextColorPreset) => {
      const fill = storyTextFillFromPreset(preset)
      setSelectedTextFill(fill)
      applyDraftToSelected({ textFill: fill })
    },
    [applyDraftToSelected]
  )

  const setCustomTextFill = useCallback(
    (fill: StoryTextFill) => {
      setSelectedTextFill(fill)
      applyDraftToSelected({ textFill: fill })
    },
    [applyDraftToSelected]
  )

  const applyTextAlignment = useCallback(
    (alignment: StoryTextAlignment) => {
      setSelectedAlignment(alignment)
      applyDraftToSelected({ alignment })
    },
    [applyDraftToSelected]
  )

  const applyTextBackground = useCallback(
    (value: boolean) => {
      setShowsTextBackground(value)
      applyDraftToSelected({ showsBackground: value })
    },
    [applyDraftToSelected]
  )

  const finishEditingText = useCallback(() => {
    setCanvas((prev) => {
      const id = prev.selectedTextID
      if (!id) return prev
      const overlay = prev.textOverlays.find((o) => o.id === id)
      if (overlay && overlay.text.trim() === "") {
        return {
          ...prev,
          textOverlays: prev.textOverlays.filter((o) => o.id !== id),
          selectedTextID: null,
        }
      }
      return prev
    })
    setIsEditingText(false)
  }, [])

  const deleteOverlay = useCallback((id: string) => {
    setCanvas((prev) => ({
      ...prev,
      textOverlays: prev.textOverlays.filter((o) => o.id !== id),
      selectedTextID: prev.selectedTextID === id ? null : prev.selectedTextID,
    }))
    setIsEditingText(false)
    setDraftText("")
  }, [])

  const deleteSelectedText = useCallback(() => {
    if (canvas.selectedTextID) deleteOverlay(canvas.selectedTextID)
  }, [canvas.selectedTextID, deleteOverlay])

  const updateOverlayPosition = useCallback(
    (id: string, normalizedCenter: { x: number; y: number }) => {
      setCanvas((prev) => {
        const index = prev.textOverlays.findIndex((o) => o.id === id)
        if (index < 0) return prev
        const next = [...prev.textOverlays]
        next[index] = { ...next[index], normalizedCenter }
        return { ...prev, textOverlays: next }
      })
    },
    []
  )

  const updateOverlayScale = useCallback((id: string, scale: number) => {
    const clamped = clampOverlayScale(scale)
    setCanvas((prev) => {
      const index = prev.textOverlays.findIndex((o) => o.id === id)
      if (index < 0) return prev
      const next = [...prev.textOverlays]
      next[index] = { ...next[index], scale: clamped }
      return { ...prev, textOverlays: next }
    })
  }, [])

  const updateOverlayRotation = useCallback(
    (id: string, rotationRadians: number) => {
      setCanvas((prev) => {
        const index = prev.textOverlays.findIndex((o) => o.id === id)
        if (index < 0) return prev
        const next = [...prev.textOverlays]
        next[index] = { ...next[index], rotationRadians }
        return { ...prev, textOverlays: next }
      })
    },
    []
  )

  const updateImageScale = useCallback((scale: number) => {
    const clamped = Math.min(Math.max(scale, 0.15), 4)
    setCanvas((prev) => ({ ...prev, imageScale: clamped }))
  }, [])

  const updateImageOffset = useCallback(
    (offset: { width: number; height: number }) => {
      setCanvas((prev) => ({ ...prev, imageOffset: offset }))
    },
    []
  )

  const resetCanvas = useCallback(() => {
    setCanvas(createEmptyStoryCanvasState())
    setIsEditingText(false)
    setDraftText("")
  }, [])

  const publishableOverlays = useMemo(
    () => publishableTextOverlays(canvas.textOverlays),
    [canvas.textOverlays]
  )

  return {
    canvas,
    canvasSize,
    setCanvasSize,
    isEditingText,
    draftText,
    selectedTextFill,
    selectedAlignment,
    showsTextBackground,
    selectedOverlay,
    publishableOverlays,
    selectText,
    beginAddingText,
    beginEditingSelectedText,
    updateDraftText,
    setSelectedColor,
    setCustomTextFill,
    applyTextAlignment,
    applyTextBackground,
    finishEditingText,
    deleteOverlay,
    deleteSelectedText,
    updateOverlayPosition,
    updateOverlayScale,
    updateOverlayRotation,
    updateImageScale,
    updateImageOffset,
    resetCanvas,
  }
}
