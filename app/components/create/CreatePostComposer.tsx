"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import FeedRoomShareCard from "@/app/components/feed/FeedRoomShareCard"
import ImageCropModal from "@/app/components/ImageCropModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { CONTENT_IMAGE_V2_PRESET } from "@/lib/contentImageV2"
import { CONTENT_IMAGE_DISPLAY_PRESET } from "@/lib/contentImagePipeline"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import { invalidateUserStreaksCache } from "@/lib/userStreaksCache"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
import { useProGate } from "@/lib/useProGate"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import { publishProfilePost } from "@/lib/publishProfilePost"
import {
  pendingRoomShareFromRoom,
  type PendingRoomShareDraft,
} from "@/lib/roomSharePost"
import { supabase } from "@/lib/supabaseClient"
import { mutationProGateFeedback } from "@/lib/mutationProGateFeedback"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { useRegisterCreatePagePrimary } from "@/app/components/create/registerCreatePagePrimary"
import type { CreatePagePrimaryRegistration } from "@/app/components/create/useCreatePagePrimaryAction"
import type { CreatePostDraftSnapshot } from "@/app/components/create/CreatePostFeedPreview"

function formatPostFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export type CreatePostComposerProps = {
  layout: "page" | "modal"
  open?: boolean
  onClose?: () => void
  onPublished?: (post: Record<string, unknown>) => void
  /** Optional room-share draft (profile deep links). */
  initialRoomShare?: PendingRoomShareDraft | null
  registerPrimary?: (update: CreatePagePrimaryRegistration) => void
  /** Live draft for create-page feed preview (no upload). */
  onDraftChange?: (draft: CreatePostDraftSnapshot) => void
}

export default function CreatePostComposer({
  layout,
  open = true,
  onClose,
  onPublished,
  initialRoomShare = null,
  registerPrimary,
  onDraftChange,
}: CreatePostComposerProps) {
  const { user, profile } = useUserProfile()
  const userId = user?.id ?? null
  const { fromError } = useProGate(profile)
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { runUpload } = useUploadProgress()

  const [postContent, setPostContent] = useState("")
  const [postImage, setPostImage] = useState<File | null>(null)
  const [pendingRoomShare, setPendingRoomShare] =
    useState<PendingRoomShareDraft | null>(initialRoomShare)
  const [creatingPost, setCreatingPost] = useState(false)
  const creatingPostRef = useRef(false)
  const uploadingPostRef = useRef(false)

  const postImageCrop = useImageCropUpload({
    preset: CONTENT_IMAGE_V2_PRESET,
    onCropped: setPostImage,
    onValidationError: (message) => showPopup({ type: "error", message }),
  })

  const [postImagePreviewUrl, setPostImagePreviewUrl] = useState<string | null>(
    null
  )

  useEffect(() => {
    if (!postImage) {
      setPostImagePreviewUrl(null)
      return
    }
    const url = URL.createObjectURL(postImage)
    setPostImagePreviewUrl(url)
    return () => URL.revokeObjectURL(url)
  }, [postImage])

  useEffect(() => {
    setPendingRoomShare(initialRoomShare)
  }, [initialRoomShare])

  useEffect(() => {
    onDraftChange?.({
      content: postContent,
      imagePreviewUrl: postImagePreviewUrl,
      pendingRoomShare,
    })
  }, [postContent, postImagePreviewUrl, pendingRoomShare, onDraftChange])

  const resetCompose = useCallback(() => {
    setPostContent("")
    setPostImage(null)
    setPendingRoomShare(null)
  }, [])

  const canPublish = useMemo(() => {
    const text = postContent.trim()
    return !!(text || postImage || pendingRoomShare)
  }, [postContent, postImage, pendingRoomShare])

  const handlePublish = useCallback(async () => {
    if (!userId) return
    if (isDemoModeActive()) {
      requestDemoSignup("comment")
      return
    }
    if (creatingPostRef.current || creatingPost || uploadingPostRef.current) {
      return
    }

    uploadingPostRef.current = true

    void import("@/lib/nativeHaptics").then(({ hapticMedium }) => {
      hapticMedium("submit-post")
    })

    try {
      await runUpload({
        title: postImage ? "Uploading Post" : "Creating Post",
        onDismissCompose: () => {
          resetCompose()
          onClose?.()
        },
        execute: async (report) => {
          creatingPostRef.current = true
          setCreatingPost(true)

          const result = await publishProfilePost(
            supabase,
            {
              userId,
              text: postContent,
              imageFile: postImage,
              pendingRoomShare,
            },
            report
          )

          if (!result.ok) {
            if (result.message.includes("Add some text")) {
              showPopup({ type: "warning", message: result.message })
            }
            throw new Error(result.message)
          }

          invalidateUserStreaksCache(userId)
          showPopup(feedbackPresets.postPublished())
          notifyGettingStartedChecklistMaybeCompleted()
          onPublished?.(result.post)
          resetCompose()
          onClose?.()
        },
      })
    } catch (err) {
      const feedback = mutationProGateFeedback(
        fromError,
        err,
        "Post Failed"
      )
      if (feedback) showPopup(feedback)
    } finally {
      creatingPostRef.current = false
      setCreatingPost(false)
      uploadingPostRef.current = false
    }
  }, [
    userId,
    creatingPost,
    runUpload,
    postContent,
    postImage,
    pendingRoomShare,
    resetCompose,
    onClose,
    onPublished,
    showPopup,
    fromError,
  ])

  useRegisterCreatePagePrimary({
    enabled: layout === "page" && open,
    registerPrimary,
    action: handlePublish,
    canAct: canPublish,
    busy: creatingPost,
  })

  if (layout === "modal" && !open) return null

  const form = (
    <>
      <textarea
        value={postContent}
        onChange={(e) => setPostContent(e.target.value)}
        placeholder={
          pendingRoomShare
            ? "Add a caption for your room share (optional)"
            : "What's on your mind?"
        }
        rows={layout === "page" ? 8 : 4}
        className="mb-4 w-full resize-none rounded-lg border border-white/10 bg-[#020617] p-3 text-sm text-white placeholder:text-gray-400 focus:border-blue-400/50 focus:outline-none focus:ring-1 focus:ring-blue-400/30"
      />

      {pendingRoomShare ? (
        <div className="mb-4">
          <FeedRoomShareCard
            post={{
              room_id: pendingRoomShare.roomId,
              room_name: pendingRoomShare.roomName,
              room_logo: pendingRoomShare.roomLogo,
              room_description: pendingRoomShare.roomDescription,
            }}
            viewerUserId={userId}
          />
        </div>
      ) : null}

      {postImagePreviewUrl ? (
        <div className="mb-4">
          <TradeScreenshotImage
            src={postImagePreviewUrl}
            preset={CONTENT_IMAGE_DISPLAY_PRESET}
            alt="Selected image preview"
            className="max-h-72 w-full rounded-xl border border-white/10 object-contain"
            logContext="create-post-preview"
          />
          {postImage ? (
            <p className="mt-1.5 text-xs text-gray-400">
              {formatPostFileSize(postImage.size)}
            </p>
          ) : null}
        </div>
      ) : null}

      <input
        type="file"
        accept="image/*"
        onChange={(e) =>
          postImageCrop.handleFileSelected(e.target.files?.[0])
        }
        className="block w-full text-sm text-gray-300 file:mr-3 file:rounded-lg file:border-0 file:bg-white/10 file:px-3 file:py-2 file:text-sm file:text-gray-100"
      />

      <ImageCropModal
        open={postImageCrop.cropSourceFile != null}
        file={postImageCrop.cropSourceFile}
        preset={CONTENT_IMAGE_V2_PRESET}
        onCancel={postImageCrop.handleCropCancel}
        onSave={postImageCrop.handleCropSave}
      />
      <FeedbackModal {...feedbackModalProps} />
    </>
  )

  if (layout === "page") {
    return form
  }

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md"
      role="presentation"
      onClick={() => {
        if (creatingPost) return
        resetCompose()
        onClose?.()
      }}
    >
      <div
        className="w-full max-w-[400px] rounded-xl border border-white/10 bg-[#0f172a] p-6 shadow-2xl"
        role="dialog"
        aria-modal="true"
        aria-labelledby="create-post-title"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-3 flex items-center justify-between">
          <h2
            id="create-post-title"
            className="text-lg font-semibold text-white"
          >
            Create Post
          </h2>
          <button
            type="button"
            onClick={() => {
              resetCompose()
              onClose?.()
            }}
            className="rounded p-1.5 text-gray-400 hover:bg-white/10 hover:text-white"
            aria-label="Close"
          >
            ✕
          </button>
        </div>
        {form}
        <button
          type="button"
          onClick={() => void handlePublish()}
          disabled={creatingPost || !canPublish}
          className="mt-4 w-full rounded-lg bg-blue-500 px-3 py-2 text-sm font-medium text-white hover:bg-blue-600 disabled:opacity-50"
        >
          Post
        </button>
      </div>
    </div>
  )
}

/** Load pending room share from sessionStorage + optional room fetch. */
export async function resolvePendingRoomShareFromQuery(
  roomId: string
): Promise<PendingRoomShareDraft | null> {
  if (!roomId) return null
  try {
    const cached = sessionStorage.getItem("pendingRoomShareDraft")
    if (cached) {
      const parsed = JSON.parse(cached) as PendingRoomShareDraft
      if (parsed?.roomId === roomId) {
        sessionStorage.removeItem("pendingRoomShareDraft")
        return parsed
      }
    }
  } catch {
    // ignore
  }

  const { data, error } = await supabase
    .from("rooms")
    .select("id, name, description, image_url")
    .eq("id", roomId)
    .maybeSingle()

  if (error || !data) return null
  return pendingRoomShareFromRoom(data)
}
