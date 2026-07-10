"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  fetchShareConversations,
  resolveShareRecipientConversationIds,
  sendImageDataUrlToConversations,
  sendPostToConversations,
  sendTradeToConversations,
  type ShareConversationRow,
} from "@/lib/shareToConversations"
import {
  collectDmPartnerUserIds,
  filterShareConversationsByQuery,
  searchProfilesForShare,
  type ShareProfileRow,
} from "@/lib/shareRecipientSearch"
import {
  copyFeedDeepLinkToClipboard,
  feedDeepLinkTargetFromShareInput,
} from "@/lib/feedDeepLink"
import { dmSendFeedback } from "@/lib/dmSendFeedback"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { FeedbackModal, ShareModalSendButton, useFeedbackPopup } from "@/app/components/ui"
import ScrollableModalShell from "@/app/components/ui/ScrollableModalShell"
import { useShareSuccessDismiss } from "@/lib/shareSuccessDismiss"
import ShareCopyLinkButton from "@/app/components/ShareCopyLinkButton"
import ShareRecipientPicker from "@/app/components/ShareRecipientPicker"
import FeedPostScreenshot from "@/app/components/feed/FeedPostScreenshot"
import { postImageSrc } from "@/app/components/feed/feedPostHelpers"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { useUserProfile } from "@/lib/useUserProfile"

export type ShareToConversationsModalProps = {
  open: boolean
  onClose: () => void
  title: string
  /** Existing trade bubble (matches feed insert). */
  tradeId?: string | null
  /** Share a feed/profile post in messages. */
  postId?: string | null
  /** Route profile wall posts to messages.profile_post_id instead of post_id. */
  feedKind?: "trade" | "profile" | "achievement" | "reel"
  /** Optional post record for screenshot preview. */
  post?: { image_url?: string | null } | null
  /** When set, uploads PNG from this data URL and sends as image messages. */
  imageDataUrlPromise?: () => Promise<string | null | undefined>
  captionPlaceholder?: string
  /** Show cancel control below send (default true). */
  showCancel?: boolean
}

export default function ShareToConversationsModal({
  open,
  onClose,
  title,
  tradeId,
  postId,
  feedKind = "trade",
  post = null,
  imageDataUrlPromise,
  captionPlaceholder = "Add a message…",
  showCancel = true,
}: ShareToConversationsModalProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const { user } = useUserProfile()
  const [shareMessage, setShareMessage] = useState("")
  const [shareConversations, setShareConversations] = useState<
    ShareConversationRow[]
  >([])
  const [selectedConversations, setSelectedConversations] = useState<string[]>(
    []
  )
  const [selectedUsers, setSelectedUsers] = useState<ShareProfileRow[]>([])
  const [searchQuery, setSearchQuery] = useState("")
  const [userResults, setUserResults] = useState<ShareProfileRow[]>([])
  const [userSearchLoading, setUserSearchLoading] = useState(false)
  const [shareLoading, setShareLoading] = useState(false)
  const { phase, isBusy, markSending, markSuccessAndDismiss, reset } =
    useShareSuccessDismiss(onClose)

  const dmPartnerIds = useMemo(
    () => collectDmPartnerUserIds(shareConversations),
    [shareConversations]
  )

  const filteredConversations = useMemo(
    () => filterShareConversationsByQuery(shareConversations, searchQuery),
    [shareConversations, searchQuery]
  )

  const selectedUserIds = useMemo(
    () => selectedUsers.map((u) => u.id),
    [selectedUsers]
  )

  const hasRecipients =
    selectedConversations.length > 0 || selectedUsers.length > 0

  const sharePostImageSrc = useMemo(
    () => (post ? postImageSrc(post.image_url) : null),
    [post]
  )

  const deepLinkTarget = useMemo(
    () => feedDeepLinkTargetFromShareInput({ postId, tradeId, feedKind }),
    [feedKind, postId, tradeId]
  )

  const successLabel = tradeId || postId ? "Shared" : "Sent"

  useEffect(() => {
    if (!open) {
      setShareMessage("")
      setSelectedConversations([])
      setSelectedUsers([])
      setShareConversations([])
      setSearchQuery("")
      setUserResults([])
      setUserSearchLoading(false)
      setShareLoading(false)
      reset()
      return
    }

    let cancelled = false

    async function load() {
      if (!user?.id || cancelled) return

      setShareLoading(true)
      const list = await fetchShareConversations(supabase, user.id)
      if (!cancelled) {
        setShareConversations(list)
        setShareLoading(false)
      }
    }

    void load()

    return () => {
      cancelled = true
    }
  }, [open, reset, user?.id])

  useEffect(() => {
    if (!open || !user?.id) return

    const query = searchQuery.trim()
    if (!query) {
      setUserResults([])
      setUserSearchLoading(false)
      return
    }

    let cancelled = false
    setUserSearchLoading(true)

    void searchProfilesForShare(
      supabase,
      user.id,
      query,
      dmPartnerIds
    ).then((rows) => {
      if (!cancelled) {
        setUserResults(rows)
        setUserSearchLoading(false)
      }
    })

    return () => {
      cancelled = true
    }
  }, [user?.id, dmPartnerIds, open, searchQuery])

  const toggleConversation = useCallback((id: string) => {
    setSelectedConversations((prev) =>
      prev.includes(id) ? prev.filter((c) => c !== id) : [...prev, id]
    )
  }, [])

  const toggleUser = useCallback((profile: ShareProfileRow) => {
    setSelectedUsers((prev) =>
      prev.some((u) => u.id === profile.id)
        ? prev.filter((u) => u.id !== profile.id)
        : [...prev, profile]
    )
  }, [])

  const handleClose = useCallback(() => {
    if (isBusy) return
    onClose()
  }, [isBusy, onClose])

  const handleCopyLink = useCallback(async () => {
    if (!deepLinkTarget) return false
    return copyFeedDeepLinkToClipboard(deepLinkTarget)
  }, [deepLinkTarget])

  const handleSend = useCallback(async () => {
    if (isDemoModeActive()) {
      requestDemoSignup("default")
      return
    }
    if (!hasRecipients || isBusy) return

    if (!user?.id) return

    markSending()

    try {
      const { conversationIds, error: resolveError } =
        await resolveShareRecipientConversationIds(
          supabase,
          user.id,
          selectedConversations,
          selectedUserIds
        )

      if (resolveError) {
        showPopup({ type: "error", message: handleSupabaseError(resolveError) })
        reset()
        return
      }

      if (postId) {
        const { error } = await sendPostToConversations(supabase, {
          senderId: user.id,
          conversationIds,
          postId,
          feedKind,
          content: shareMessage.trim() || undefined,
        })
        if (error) {
          showPopup(dmSendFeedback(error, "Share Failed"))
          reset()
          return
        }
      } else if (tradeId) {
        const { error } = await sendTradeToConversations(supabase, {
          senderId: user.id,
          conversationIds,
          tradeId,
          content: shareMessage.trim() || undefined,
        })
        if (error) {
          showPopup(dmSendFeedback(error, "Share Failed"))
          reset()
          return
        }
      } else if (imageDataUrlPromise) {
        const dataUrl = await imageDataUrlPromise()
        if (!dataUrl) {
          showPopup({ type: "error", message: "Could not capture image." })
          reset()
          return
        }
        const { error } = await sendImageDataUrlToConversations(supabase, {
          senderId: user.id,
          conversationIds,
          dataUrl,
          content: shareMessage.trim() || "",
        })
        if (error) {
          showPopup(dmSendFeedback(error, "Share Failed"))
          reset()
          return
        }
      }

      markSuccessAndDismiss()
    } catch {
      reset()
    }
  }, [
    hasRecipients,
    imageDataUrlPromise,
    isBusy,
    markSending,
    markSuccessAndDismiss,
    postId,
    feedKind,
    reset,
    selectedConversations,
    selectedUserIds,
    shareMessage,
    showPopup,
    tradeId,
    user?.id,
  ])

  if (!open) return null

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <ScrollableModalShell
        open={open}
        onClose={handleClose}
        ariaLabel={title}
        showCloseButton={false}
        overlayClassName="z-[9999] bg-black/50 backdrop-blur-sm"
        backdropClassName="bg-transparent"
        panelClassName="max-w-[400px] rounded-xl border-white/10 bg-[#0f172a]"
        headerClassName="border-white/10 px-4 py-4"
        bodyClassName="px-4"
        footerClassName="border-white/10 px-4 py-4"
        closeDisabled={isBusy}
        header={<h2 className="text-lg font-semibold text-white">{title}</h2>}
        footer={
          <>
            <ShareModalSendButton
              phase={phase}
              onClick={() => void handleSend()}
              disabled={!hasRecipients || shareLoading}
              successLabel={successLabel}
            />
            {showCancel ? (
              <button
                type="button"
                onClick={handleClose}
                disabled={isBusy}
                className="mt-2 w-full text-sm text-gray-400 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
              >
                Cancel
              </button>
            ) : null}
          </>
        }
      >
          {deepLinkTarget ? (
            <ShareCopyLinkButton
              className="mb-3"
              onCopy={handleCopyLink}
              onCopyError={() =>
                showPopup({ type: "error", message: "Could not copy link." })
              }
            />
          ) : null}

          {postId && sharePostImageSrc != null ? (
            <div className="mb-3">
              <FeedPostScreenshot
                imageSrc={sharePostImageSrc}
                wrapperClassName=""
              />
            </div>
          ) : null}

          <textarea
            placeholder={captionPlaceholder}
            value={shareMessage}
            onChange={(e) => setShareMessage(e.target.value)}
            className="mb-3 w-full resize-none rounded bg-white/5 p-2 text-sm"
            rows={postId ? undefined : 2}
          />

          <ShareRecipientPicker
            conversations={shareConversations}
            loading={shareLoading}
            searchQuery={searchQuery}
            onSearchQueryChange={setSearchQuery}
            filteredConversations={filteredConversations}
            userResults={userResults}
            userSearchLoading={userSearchLoading}
            selectedConversationIds={selectedConversations}
            selectedUserIds={selectedUserIds}
            onToggleConversation={toggleConversation}
            onToggleUser={toggleUser}
          />
      </ScrollableModalShell>
    </>
  )
}
