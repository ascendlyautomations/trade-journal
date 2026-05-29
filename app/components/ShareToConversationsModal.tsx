"use client"

import { useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  fetchShareConversations,
  sendImageDataUrlToConversations,
  sendTradeToConversations,
  type ShareConversationRow,
} from "@/lib/shareToConversations"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"

export type ShareToConversationsModalProps = {
  open: boolean
  onClose: () => void
  title: string
  /** Existing trade bubble (matches feed insert). */
  tradeId?: string | null
  /** When set, uploads PNG from this data URL and sends as image messages. */
  imageDataUrlPromise?: () => Promise<string | null | undefined>
  /** Optional caption when sending an image only. */
  captionPlaceholder?: string
}

export default function ShareToConversationsModal({
  open,
  onClose,
  title,
  tradeId,
  imageDataUrlPromise,
  captionPlaceholder = "Add a message…",
}: ShareToConversationsModalProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [shareMessage, setShareMessage] = useState("")
  const [shareConversations, setShareConversations] = useState<
    ShareConversationRow[]
  >([])
  const [selectedConversations, setSelectedConversations] = useState<string[]>(
    []
  )
  const [shareLoading, setShareLoading] = useState(false)
  const [sending, setSending] = useState(false)

  useEffect(() => {
    if (!open) {
      setShareMessage("")
      setSelectedConversations([])
      setShareConversations([])
      setShareLoading(false)
      setSending(false)
      return
    }

    let cancelled = false

    async function load() {
      const {
        data: { user },
      } = await supabase.auth.getUser()
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
  }, [open])

  function toggleConversation(id: string) {
    setSelectedConversations((prev) =>
      prev.includes(id) ? prev.filter((c) => c !== id) : [...prev, id]
    )
  }

  async function handleSend() {
    if (selectedConversations.length === 0) return

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user?.id) return

    setSending(true)

    try {
      if (tradeId) {
        const msg = shareMessage.trim() || "Shared a trade"
        const { error } = await sendTradeToConversations(supabase, {
          senderId: user.id,
          conversationIds: selectedConversations,
          tradeId,
          content: msg,
        })
        if (error) {
          showPopup({ type: "error", message: handleSupabaseError(error) })
          return
        }
      } else if (imageDataUrlPromise) {
        const dataUrl = await imageDataUrlPromise()
        if (!dataUrl) {
          showPopup({ type: "error", message: "Could not capture image." })
          return
        }
        const { error } = await sendImageDataUrlToConversations(supabase, {
          senderId: user.id,
          conversationIds: selectedConversations,
          dataUrl,
          content: shareMessage.trim() || "",
        })
        if (error) {
          showPopup({ type: "error", message: handleSupabaseError(error) })
          return
        }
      }

      onClose()
    } finally {
      setSending(false)
    }
  }

  if (!open) return null

  return (
    <>
      <FeedbackModal {...feedbackModalProps} />
      <div
      className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 backdrop-blur-sm"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="w-full max-w-md bg-[#0b1f3a] rounded-2xl shadow-xl p-6 text-white"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 className="mb-3 text-lg font-semibold">{title}</h2>

        <textarea
          placeholder={captionPlaceholder}
          value={shareMessage}
          onChange={(e) => setShareMessage(e.target.value)}
          className="mb-3 w-full resize-none rounded bg-white/5 p-2 text-sm"
          rows={2}
        />

        {shareLoading ? (
          <p className="text-sm text-gray-400">Loading chats…</p>
        ) : shareConversations.length === 0 ? (
          <p className="text-sm text-gray-400">No chats found.</p>
        ) : (
          <div className="max-h-40 space-y-2 overflow-y-auto">
            {shareConversations.map((conv) => (
              <button
                key={conv.id}
                type="button"
                onClick={() => toggleConversation(conv.id)}
                className={`flex w-full cursor-pointer items-center gap-3 rounded p-2 text-left ${
                  selectedConversations.includes(conv.id)
                    ? "bg-blue-500/20"
                    : "hover:bg-white/10"
                }`}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={conv.avatar_url || "/default-avatar.png"}
                  className="h-8 w-8 rounded-full object-cover"
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
          onClick={() => void handleSend()}
          disabled={
            selectedConversations.length === 0 || sending || shareLoading
          }
          className="mt-3 w-full rounded bg-blue-600 p-2 hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {sending ? "Sending…" : "Send"}
        </button>

        <button
          type="button"
          onClick={onClose}
          className="mt-2 w-full text-sm text-gray-400 hover:text-white"
        >
          Cancel
        </button>
      </div>
    </div>
    </>
  )
}
