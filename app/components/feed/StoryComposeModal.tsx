"use client"

import { useEffect, useRef, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import StoryEditorPanel from "@/app/components/create/StoryEditorPanel"
import type { StoryBarProfile } from "./FeedStoriesBar"
import { prepareStoryUploadFile } from "@/lib/storyEditor/prepareStoryUploadFile"
import { useStoryEditorState } from "@/lib/storyEditor/useStoryEditorState"

type StoryComposeModalProps = {
  open: boolean
  posting: boolean
  profile: StoryBarProfile | null
  storyFile: File | null
  previewUrl: string | null
  onClose: () => void
  /** Receives the baked upload file (with text composited when needed). */
  onPost: (uploadFile: File) => void
  onReplaceImage: (file: File) => void
}

export default function StoryComposeModal({
  open,
  posting,
  profile,
  storyFile,
  previewUrl,
  onClose,
  onPost,
  onReplaceImage,
}: StoryComposeModalProps) {
  const replaceInputRef = useRef<HTMLInputElement>(null)
  const editor = useStoryEditorState()
  const { resetCanvas } = editor
  const [showEditorIntro, setShowEditorIntro] = useState(false)

  useEffect(() => {
    if (open && storyFile) {
      resetCanvas()
      setShowEditorIntro(true)
    }
  }, [open, storyFile, resetCanvas])

  if (!profile || !previewUrl || !storyFile) return null

  return (
    <Modal
      open={open}
      onClose={() => {
        if (!posting) onClose()
      }}
      title="Create Story"
      size="md"
      panelClassName="max-w-md p-4 sm:p-6"
      footer={
        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button
            type="button"
            disabled={posting}
            onClick={onClose}
            className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={posting}
            onClick={() => {
              void (async () => {
                const uploadFile = await prepareStoryUploadFile(
                  storyFile,
                  editor.canvas,
                  editor.canvasSize
                )
                onPost(uploadFile)
              })()
            }}
            className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:opacity-50 disabled:hover:bg-blue-500"
          >
            Post Story
          </button>
        </div>
      }
    >
      <StoryEditorPanel
        storyFile={storyFile}
        imageUrl={previewUrl}
        editor={editor}
        layout="compact"
        showEditorIntro={showEditorIntro}
        onDismissEditorIntro={() => setShowEditorIntro(false)}
      />

      <input
        ref={replaceInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0]
          e.target.value = ""
          if (file) onReplaceImage(file)
        }}
      />

      <button
        type="button"
        disabled={posting}
        onClick={() => replaceInputRef.current?.click()}
        className="mt-4 w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
      >
        Change image
      </button>
    </Modal>
  )
}
