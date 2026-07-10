"use client"

import { useRef } from "react"
import Modal from "@/app/components/ui/Modal"
import StoryFrame from "./StoryFrame"
import type { StoryBarProfile } from "./FeedStoriesBar"

type StoryComposeModalProps = {
  open: boolean
  posting: boolean
  profile: StoryBarProfile | null
  previewUrl: string | null
  onClose: () => void
  onPost: () => void
  onReplaceImage: (file: File) => void
}

export default function StoryComposeModal({
  open,
  posting,
  profile,
  previewUrl,
  onClose,
  onPost,
  onReplaceImage,
}: StoryComposeModalProps) {
  const replaceInputRef = useRef<HTMLInputElement>(null)

  if (!profile || !previewUrl) return null

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
            onClick={onPost}
            className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:opacity-50 disabled:hover:bg-blue-500"
          >
            Post Story
          </button>
        </div>
      }
    >
      <p className="mb-3 text-sm text-gray-400">
        Preview how your story will appear before posting.
      </p>

      <div className="mx-auto flex w-full max-w-[240px] justify-center sm:max-w-[274px]">
        <StoryFrame
          profile={profile}
          imageUrl={previewUrl}
          imageKey={previewUrl}
          className="aspect-[400/700] w-full rounded-2xl border border-white/10 shadow-lg shadow-black/40"
        />
      </div>

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
