"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { fetchShareConversations } from "@/lib/shareToConversations"
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { logSupabaseError } from "@/lib/logSupabaseError"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import FeedPostScreenshot from "./FeedPostScreenshot"
import { postImageSrc } from "./feedPostHelpers"

type FeedSharePostOverlayProps = {
  post: any
  user: any
  onClose: () => void
}

export default function FeedSharePostOverlay({
  post,
  user,
  onClose,
}: FeedSharePostOverlayProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [shareMessage, setShareMessage] = useState("")
  const [shareConversations, setShareConversations] = useState<any[]>([])
  const [selectedConversations, setSelectedConversations] = useState<string[]>([])
  const [shareLoading, setShareLoading] = useState(false)
  const [sending, setSending] = useState(false)
  const sendingRef = useRef(false)

  const sharePostImageSrc = useMemo(
    () => postImageSrc(post.image_url),
    [post.image_url]
  )

  useEffect(() => {
    if (!user?.id) return

    let cancelled = false
    const loadShareConversations = async () => {
      setShareLoading(true)
      const list = await fetchShareConversations(supabase, user.id)
      if (!cancelled) {
        setShareConversations(list)
        setShareLoading(false)
      }
    }

    void loadShareConversations()
    return () => {
      cancelled = true
    }
  }, [user?.id])

  const handleClose = useCallback(() => {
    onClose()
  }, [onClose])

  const toggleConversation = useCallback((id: string) => {
    setSelectedConversations((prev) =>
      prev.includes(id) ? prev.filter((c) => c !== id) : [...prev, id]
    )
  }, [])

  const handleSendPost = useCallback(async () => {
    if (selectedConversations.length === 0) return
    if (sendingRef.current || sending) return

    sendingRef.current = true
    setSending(true)

    try {
    const {
      data: { user: authUser },
    } = await supabase.auth.getUser()

    if (!authUser?.id) return

    const userIsPro = await isUserPro(supabase as any, authUser.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        authUser.id,
        10
      )
      if (limitReached) {
        showPopup(feedbackPresets.messageLimit())
        return
      }
    }

    const content = shareMessage.trim() || "Shared a post"

    for (const conversationId of selectedConversations) {
      const payload = {
        conversation_id: conversationId,
        sender_id: authUser.id,
        type: "post",
        post_id: post.id,
        content,
        channel: null,
      }
      const { error } = await supabase.from("messages").insert(payload)

      if (error) {
        logSupabaseError("FeedSharePostOverlay messages insert", error, {
          table: "messages",
          query: "insert",
          payload,
          userId: authUser.id,
          conversationId,
        })
        showPopup({ type: "error", message: handleSupabaseError(error) })
        return
      }
    }

    onClose()
    } finally {
      sendingRef.current = false
      setSending(false)
    }
  }, [onClose, post.id, selectedConversations, shareMessage, showPopup, sending])

  const stopPropagation = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
  }, [])

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <div
      className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4"
      onClick={handleClose}
    >
      <div
        className="w-full max-w-[400px] rounded-xl border border-white/10 bg-[#0f172a] p-4 text-white"
        onClick={stopPropagation}
      >
        <h2 className="text-lg font-semibold mb-3">Send Post</h2>

        <div className="mb-3">
          <FeedPostScreenshot
            imageSrc={sharePostImageSrc}
            imgClassName="w-full h-40 object-cover rounded"
            wrapperClassName=""
          />
        </div>

        <textarea
          placeholder="Add a message..."
          value={shareMessage}
          onChange={(e) => setShareMessage(e.target.value)}
          className="w-full p-2 bg-white/5 rounded mb-3"
        />

        {shareLoading ? (
          <p className="text-sm text-gray-400">Loading chats...</p>
        ) : shareConversations.length === 0 ? (
          <p className="text-sm text-gray-400">No chats found.</p>
        ) : (
          <div className="max-h-40 overflow-y-auto space-y-2">
            {shareConversations.map((conv) => (
              <button
                key={conv.id}
                type="button"
                onClick={() => toggleConversation(conv.id)}
                className={`w-full flex items-center gap-3 p-2 rounded cursor-pointer text-left ${
                  selectedConversations.includes(conv.id)
                    ? "bg-blue-500/20"
                    : "hover:bg-white/10"
                }`}
              >
                <img
                  src={conv.avatar_url || "/default-avatar.png"}
                  className="w-8 h-8 rounded-full object-cover"
                  alt=""
                  loading="lazy"
                  decoding="async"
                />
                <span>{conv.name || (conv.is_group ? "Group Chat" : "Chat")}</span>
              </button>
            ))}
          </div>
        )}

        <button
          type="button"
          onClick={() => void handleSendPost()}
          disabled={selectedConversations.length === 0 || sending}
          className="mt-3 w-full rounded bg-blue-600 p-2 hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {sending ? "Sending…" : "Send"}
        </button>
      </div>
    </div>
    </>
  )
}
