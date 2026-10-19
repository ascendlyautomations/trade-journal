"use client"

import type { ChangeEvent } from "react"
import { useCallback, useEffect, useRef, useState } from "react"
import StoryEditorPanel from "@/app/components/create/StoryEditorPanel"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { prepareStoryUploadFile } from "@/lib/storyEditor/prepareStoryUploadFile"
import { useStoryEditorState } from "@/lib/storyEditor/useStoryEditorState"
import { publishStory } from "@/lib/publishStory"
import {
  createStoryPreviewUrl,
  revokeStoryPreviewUrl,
  validateStorySourceFile,
} from "@/lib/storyComposeHelpers"
import { supabase } from "@/lib/supabaseClient"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { useRegisterCreatePagePrimary } from "@/app/components/create/registerCreatePagePrimary"
import type { CreatePagePrimaryRegistration } from "@/app/components/create/useCreatePagePrimaryAction"

export type CreateStoryComposerProps = {
  layout: "page" | "modal"
  open?: boolean
  onClose?: () => void
  onPosted?: () => void
  registerPrimary?: (update: CreatePagePrimaryRegistration) => void
}

export default function CreateStoryComposer({
  layout,
  open = true,
  onClose,
  onPosted,
  registerPrimary,
}: CreateStoryComposerProps) {
  const { user, profile } = useUserProfile()
  const userId = user?.id ?? null
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { runUpload } = useUploadProgress()
  const storyEditor = useStoryEditorState()
  const {
    canvas: storyCanvas,
    canvasSize: storyCanvasSize,
    resetCanvas: resetStoryCanvas,
  } = storyEditor

  const fileInputRef = useRef<HTMLInputElement>(null)
  const [pendingStoryFile, setPendingStoryFile] = useState<File | null>(null)
  const [pendingStoryPreviewUrl, setPendingStoryPreviewUrl] = useState<
    string | null
  >(null)
  const [showEditorIntro, setShowEditorIntro] = useState(false)
  const [postingStory, setPostingStory] = useState(false)
  const postingStoryRef = useRef(false)
  const uploadingStoryRef = useRef(false)

  const storyProfile =
    profile && userId
      ? {
          id: userId,
          username: profile.username,
          avatar_url: profile.avatar_url,
        }
      : null

  const reset = useCallback(() => {
    revokeStoryPreviewUrl(pendingStoryPreviewUrl)
    setPendingStoryPreviewUrl(null)
    setPendingStoryFile(null)
    setShowEditorIntro(false)
    resetStoryCanvas()
  }, [pendingStoryPreviewUrl, resetStoryCanvas])

  const enterStoryEditor = useCallback(
    (file: File) => {
      const validationError = validateStorySourceFile(file)
      if (validationError) {
        showPopup({ type: "error", message: validationError })
        return
      }
      revokeStoryPreviewUrl(pendingStoryPreviewUrl)
      resetStoryCanvas()
      setPendingStoryFile(file)
      setPendingStoryPreviewUrl(createStoryPreviewUrl(file))
      setShowEditorIntro(true)
    },
    [pendingStoryPreviewUrl, resetStoryCanvas, showPopup]
  )

  const handleFileSelect = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0]
      e.target.value = ""
      if (!file || !userId) return
      enterStoryEditor(file)
    },
    [enterStoryEditor, userId]
  )

  const handlePostStory = useCallback(async () => {
    if (isDemoModeActive()) {
      requestDemoSignup("upload")
      return
    }
    if (
      !pendingStoryFile ||
      !userId ||
      postingStoryRef.current ||
      postingStory ||
      uploadingStoryRef.current
    ) {
      return
    }

    uploadingStoryRef.current = true

    try {
      const uploadFile = await prepareStoryUploadFile(
        pendingStoryFile,
        storyCanvas,
        storyCanvasSize
      )

      await runUpload({
        title: "Uploading Story",
        onDismissCompose: () => {
          reset()
          onClose?.()
        },
        execute: async (report) => {
          postingStoryRef.current = true
          setPostingStory(true)

          const result = await publishStory(supabase, userId, uploadFile, {
            onProgress: report,
          })

          if (!result.ok) {
            throw new Error(result.message)
          }

          showPopup({ type: "success", message: "Story uploaded!" })
          reset()
          onPosted?.()
          onClose?.()
        },
      })
    } catch (error) {
      showPopup({
        type: "error",
        message:
          error instanceof Error ? error.message : "Couldn't post story",
      })
    } finally {
      postingStoryRef.current = false
      setPostingStory(false)
      uploadingStoryRef.current = false
    }
  }, [
    pendingStoryFile,
    userId,
    postingStory,
    runUpload,
    reset,
    onClose,
    onPosted,
    showPopup,
    storyCanvas,
    storyCanvasSize,
  ])

  const canPost = !!pendingStoryFile && !!pendingStoryPreviewUrl

  useRegisterCreatePagePrimary({
    enabled: layout === "page",
    registerPrimary,
    action: handlePostStory,
    canAct: canPost,
    busy: postingStory,
  })

  useEffect(() => {
    return () => revokeStoryPreviewUrl(pendingStoryPreviewUrl)
  }, [pendingStoryPreviewUrl])

  if (layout === "modal" && !open) return null

  const uploadZone = (
    <>
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={handleFileSelect}
      />
      {!pendingStoryPreviewUrl || !pendingStoryFile ? (
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          className={`flex w-full flex-col items-center justify-center gap-3 rounded-xl border border-dashed border-white/20 bg-white/5 text-center transition hover:border-emerald-400/40 hover:bg-emerald-500/10 ${
            layout === "page" ? "min-h-[240px] px-6 py-16 sm:min-h-[320px]" : "px-4 py-10"
          }`}
        >
          <span className="text-3xl" aria-hidden>
            📷
          </span>
          <span className="text-base font-medium text-white">Add a photo</span>
          <span className="max-w-sm text-sm text-gray-400">
            Drag to reposition, pinch or Ctrl+scroll to zoom, then add text
            before posting.
          </span>
        </button>
      ) : (
        <div className="space-y-4">
          <StoryEditorPanel
            storyFile={pendingStoryFile}
            imageUrl={pendingStoryPreviewUrl}
            editor={storyEditor}
            profile={storyProfile}
            showFeedPreview={layout === "page"}
            layout={layout === "page" ? "page" : "compact"}
            showEditorIntro={showEditorIntro}
            onDismissEditorIntro={() => setShowEditorIntro(false)}
          />
          <button
            type="button"
            disabled={postingStory}
            onClick={() => fileInputRef.current?.click()}
            className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2.5 text-sm text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
          >
            Change image
          </button>
        </div>
      )}
      <FeedbackModal {...feedbackModalProps} />
    </>
  )

  if (layout === "page") {
    return uploadZone
  }

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md">
      <div className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-6">
        <h2 className="mb-4 text-lg font-semibold text-white">Create Story</h2>
        {uploadZone}
        <div className="mt-4 flex gap-2">
          <button
            type="button"
            onClick={() => {
              reset()
              onClose?.()
            }}
            className="flex-1 rounded-lg border border-white/10 bg-white/5 py-2 text-sm text-gray-200"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={!canPost || postingStory}
            onClick={() => void handlePostStory()}
            className="flex-1 rounded-lg bg-blue-500 py-2 text-sm font-medium text-white disabled:opacity-50"
          >
            Post Story
          </button>
        </div>
      </div>
    </div>
  )
}
