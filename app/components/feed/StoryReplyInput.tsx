"use client"

import { memo, useCallback, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { sendStoryReply } from "@/lib/sendStoryReply"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"

type StoryReplyInputProps = {
  currentUserId: string
  storyOwnerId: string
  storyOwnerUsername?: string | null
  story: { id: string; image_url: string }
  onSent?: () => void
  onError?: (message: string) => void
}

function SendIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden
    >
      <path d="M3.4 20.6 21 12 3.4 3.4l1.8 7.2L16 12l-10.8 1.4-1.8 7.2z" />
    </svg>
  )
}

function StoryReplyInput({
  currentUserId,
  storyOwnerId,
  storyOwnerUsername,
  story,
  onSent,
  onError,
}: StoryReplyInputProps) {
  const [text, setText] = useState("")
  const [sending, setSending] = useState(false)

  const submit = useCallback(async () => {
    const trimmed = text.trim()
    if (!trimmed || sending) return

    if (isDemoModeActive()) {
      requestDemoSignup("comment")
      return
    }

    setSending(true)
    try {
      const result = await sendStoryReply(supabase, {
        senderId: currentUserId,
        storyOwnerId,
        story,
        storyOwnerUsername,
        text: trimmed,
      })

      if (!result.ok) {
        onError?.(result.error)
        return
      }

      setText("")
      onSent?.()
    } catch (err) {
      onError?.(handleSupabaseError(err))
    } finally {
      setSending(false)
    }
  }, [
    currentUserId,
    onError,
    onSent,
    sending,
    story,
    storyOwnerId,
    storyOwnerUsername,
    text,
  ])

  if (currentUserId === storyOwnerId) return null

  return (
    <div
      className="border-t border-white/10 bg-gradient-to-t from-black via-black/95 to-black/70 px-3 py-3"
      onClick={(e) => e.stopPropagation()}
      onKeyDown={(e) => e.stopPropagation()}
    >
      <div className="flex items-center gap-2">
        <input
          type="text"
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault()
              void submit()
            }
          }}
          placeholder="Reply to story..."
          disabled={sending}
          className="min-w-0 flex-1 rounded-full border border-white/15 bg-white/10 px-4 py-2.5 text-sm text-white placeholder:text-gray-400 focus:border-emerald-400/50 focus:outline-none focus:ring-1 focus:ring-emerald-400/30 disabled:opacity-60"
        />
        <button
          type="button"
          aria-label="Send story reply"
          onClick={() => void submit()}
          disabled={sending || !text.trim()}
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-blue-500 text-white transition hover:bg-blue-600 disabled:pointer-events-none disabled:opacity-40 disabled:hover:bg-blue-500"
        >
          <SendIcon className="h-4 w-4" />
        </button>
      </div>
    </div>
  )
}

export default memo(StoryReplyInput)
