"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { fetchShareConversations } from "@/lib/shareToConversations"
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
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
  const [shareMessage, setShareMessage] = useState("")
  const [shareConversations, setShareConversations] = useState<any[]>([])
  const [selectedConversations, setSelectedConversations] = useState<string[]>([])
  const [shareLoading, setShareLoading] = useState(false)

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
        alert(handleSupabaseError({ message: "10 messages limit" }))
        return
      }
    }

    const content = shareMessage.trim() || "Shared a post"

    for (const conversationId of selectedConversations) {
      const { error } = await supabase.from("messages").insert({
        conversation_id: conversationId,
        sender_id: authUser.id,
        type: "post",
        post_id: post.id,
        content,
      })

      if (error) {
        console.error("Share post error:", error)
        alert(handleSupabaseError(error))
        return
      }
    }

    onClose()
  }, [onClose, post.id, selectedConversations, shareMessage])

  const stopPropagation = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
  }, [])

  return (
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
          disabled={selectedConversations.length === 0}
          className="w-full mt-3 bg-blue-600 hover:bg-blue-700 p-2 rounded disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Send
        </button>
      </div>
    </div>
  )
}
