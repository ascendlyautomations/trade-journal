"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import StoryEditorCanvas from "./StoryEditorCanvas"
import StoryTextEditingChrome from "./StoryTextEditingChrome"
import StoryFrame from "@/app/components/feed/StoryFrame"
import Button from "@/app/components/ui/Button"
import type { StoryBarProfile } from "@/app/components/feed/FeedStoriesBar"
import type { useStoryEditorState } from "@/lib/storyEditor/useStoryEditorState"
import {
  loadImageFromFile,
  renderStoryToBlob,
} from "@/lib/storyEditor/storyImageRenderer"

export type StoryEditorPanelProps = {
  storyFile: File
  imageUrl: string
  editor: ReturnType<typeof useStoryEditorState>
  profile?: StoryBarProfile | null
  showFeedPreview?: boolean
  layout?: "page" | "compact"
  /** Shown once after picking a photo — explains unified editor. */
  showEditorIntro?: boolean
  onDismissEditorIntro?: () => void
}

export default function StoryEditorPanel({
  storyFile,
  imageUrl,
  editor,
  profile,
  showFeedPreview = false,
  layout = "page",
  showEditorIntro = false,
  onDismissEditorIntro,
}: StoryEditorPanelProps) {
  const [imageNaturalSize, setImageNaturalSize] = useState<{
    width: number
    height: number
  } | null>(null)
  const [previewObjectUrl, setPreviewObjectUrl] = useState<string | null>(null)
  const textAreaFocusRef = useRef<HTMLTextAreaElement | null>(null)

  const handleAddText = useCallback(() => {
    onDismissEditorIntro?.()
    editor.beginAddingText()
  }, [editor, onDismissEditorIntro])

  useEffect(() => {
    if (editor.isEditingText) {
      textAreaFocusRef.current?.focus()
    }
  }, [editor.isEditingText, editor.canvas.selectedTextID])

  useEffect(() => {
    let cancelled = false
    void loadImageFromFile(storyFile).then((img) => {
      if (cancelled) return
      setImageNaturalSize({ width: img.naturalWidth, height: img.naturalHeight })
    })
    return () => {
      cancelled = true
    }
  }, [storyFile])

  useEffect(() => {
    if (!showFeedPreview || editor.canvasSize.width <= 0) {
      setPreviewObjectUrl((prev) => {
        if (prev?.startsWith("blob:")) URL.revokeObjectURL(prev)
        return null
      })
      return
    }

    let cancelled = false
    const timer = window.setTimeout(() => {
      void (async () => {
        try {
          const img = await loadImageFromFile(storyFile)
          const blob = await renderStoryToBlob({
            sourceImage: img,
            canvas: editor.canvas,
            canvasSize: editor.canvasSize,
          })
          if (cancelled) return
          const url = URL.createObjectURL(blob)
          setPreviewObjectUrl((prev) => {
            if (prev?.startsWith("blob:")) URL.revokeObjectURL(prev)
            return url
          })
        } catch {
          // optional preview
        }
      })()
    }, 150)

    return () => {
      cancelled = true
      window.clearTimeout(timer)
    }
  }, [editor.canvas, editor.canvasSize, showFeedPreview, storyFile])

  useEffect(() => {
    return () => {
      if (previewObjectUrl?.startsWith("blob:")) {
        URL.revokeObjectURL(previewObjectUrl)
      }
    }
  }, [previewObjectUrl])

  const editorBlock = (
    <StoryEditorCanvas
      imageUrl={imageUrl}
      imageNaturalSize={imageNaturalSize}
      editor={editor}
      onAddText={handleAddText}
      addTextDisabled={editor.isEditingText}
    />
  )

  const toolbar = (
    <div
      className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between"
      data-testid="story-editor-toolbar"
    >
      <div className="min-w-0">
        <p className="text-sm font-semibold text-white">Edit your story</p>
        <p className="text-xs text-gray-300">
          Drag the photo to reposition; pinch or Ctrl+scroll to zoom.
        </p>
      </div>
      <Button
        type="button"
        variant="secondary"
        size="md"
        className="shrink-0 border-emerald-400/40 bg-emerald-500/15 text-emerald-100 hover:bg-emerald-500/25"
        onClick={handleAddText}
        disabled={editor.isEditingText}
        data-testid="story-editor-add-text-button"
      >
        Add text
      </Button>
    </div>
  )

  const introBanner =
    showEditorIntro && !editor.isEditingText ? (
      <div
        role="status"
        className="rounded-lg border border-emerald-400/35 bg-emerald-500/15 px-3 py-2.5 text-sm text-emerald-100"
      >
        Adjust your photo in the frame (drag / pinch / Ctrl+scroll), then tap{" "}
        <span className="font-semibold text-white">Add text</span> or{" "}
        <span className="font-semibold text-white">Aa</span> for captions.
      </div>
    ) : null

  const chrome = editor.isEditingText ? (
    <StoryTextEditingChrome
      draftText={editor.draftText}
      selectedTextFill={editor.selectedTextFill}
      selectedAlignment={editor.selectedAlignment}
      showsTextBackground={editor.showsTextBackground}
      textScale={editor.selectedOverlay?.scale ?? 1}
      onTextScaleChange={(scale) => {
        const id = editor.canvas.selectedTextID
        if (id) editor.updateOverlayScale(id, scale)
      }}
      onDraftChange={editor.updateDraftText}
      onSelectPreset={editor.setSelectedColor}
      onCustomFillChange={editor.setCustomTextFill}
      onAlignmentChange={editor.applyTextAlignment}
      onBackgroundChange={editor.applyTextBackground}
      onDelete={editor.deleteSelectedText}
      onDone={editor.finishEditingText}
      textAreaRef={textAreaFocusRef}
    />
  ) : (
    <p className="text-xs text-gray-300">
      Tap the canvas to adjust the photo when no text is selected. While
      editing text, use Text size or drag the overlay; pinch or Ctrl+scroll also
      resize.
    </p>
  )

  const editorColumn = (
    <div className="space-y-3">
      {toolbar}
      {introBanner}
      {editorBlock}
      {chrome}
    </div>
  )

  if (layout === "compact") {
    return editorColumn
  }

  return (
    <div
      className={
        showFeedPreview && profile
          ? "grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(240px,320px)] lg:items-start"
          : "space-y-4"
      }
    >
      {editorColumn}
      {showFeedPreview && profile && previewObjectUrl ? (
        <div className="space-y-2">
          <p className="text-sm text-gray-300">Feed preview</p>
          <StoryFrame
            profile={profile}
            imageUrl={previewObjectUrl}
            imageKey={previewObjectUrl}
            className="aspect-[400/700] w-full max-w-[280px] rounded-2xl border border-white/10 shadow-lg shadow-black/40 lg:max-w-none"
          />
        </div>
      ) : null}
    </div>
  )
}
