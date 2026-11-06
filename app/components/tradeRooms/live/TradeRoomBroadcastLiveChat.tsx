"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import Image from "next/image"
import { supabase } from "@/lib/supabaseClient.ts"
import {
  getTradeRoomBroadcastRoom,
  sendTradeRoomBroadcastChatMessage,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import type { BroadcastChatMessage } from "@/lib/livekit/client/tradeRoomBroadcastChat.ts"
import {
  peekBroadcastChatProfile,
  resolveBroadcastChatProfiles,
  seedBroadcastChatProfile,
  type BroadcastChatProfile,
} from "@/lib/livekit/client/tradeRoomBroadcastChatProfiles.ts"

type Props = {
  messages: BroadcastChatMessage[]
  userId: string | null
  displayName: string
  avatarUrl: string | null
  disabled?: boolean
}

function ChatAvatar({
  profile,
}: {
  profile: BroadcastChatProfile | undefined
}) {
  const label = profile?.displayName?.charAt(0)?.toUpperCase() ?? "?"
  const src = profile?.avatarUrl
  if (src) {
    return (
      <Image
        src={src}
        alt=""
        width={28}
        height={28}
        className="h-7 w-7 shrink-0 rounded-full object-cover"
        unoptimized
      />
    )
  }
  return (
    <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-white/10 text-xs font-semibold text-gray-300">
      {label}
    </span>
  )
}

export default function TradeRoomBroadcastLiveChat({
  messages,
  userId,
  displayName,
  avatarUrl,
  disabled,
}: Props) {
  const [draft, setDraft] = useState("")
  const [sendError, setSendError] = useState<string | null>(null)
  const [profiles, setProfiles] = useState<Map<string, BroadcastChatProfile>>(
    () => new Map()
  )
  const listRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (userId) {
      seedBroadcastChatProfile({
        userId,
        displayName,
        avatarUrl,
      })
    }
  }, [userId, displayName, avatarUrl])

  useEffect(() => {
    const ids = messages.map((m) => m.userId)
    if (ids.length === 0) return
    let cancelled = false
    void resolveBroadcastChatProfiles(supabase, ids).then((map) => {
      if (cancelled) return
      setProfiles((prev) => {
        const next = new Map(prev)
        for (const [id, p] of map) next.set(id, p)
        return next
      })
    })
    return () => {
      cancelled = true
    }
  }, [messages])

  useEffect(() => {
    const el = listRef.current
    if (!el) return
    el.scrollTop = el.scrollHeight
  }, [messages.length])

  const onSend = useCallback(async () => {
    if (!userId || !draft.trim() || disabled) return
    if (!getTradeRoomBroadcastRoom()) {
      setSendError("Not connected to chat.")
      return
    }
    setSendError(null)
    const verified = peekBroadcastChatProfile(userId)
    const result = await sendTradeRoomBroadcastChatMessage({
      userId,
      displayName: verified?.displayName ?? displayName,
      avatarUrl: null,
      text: draft,
    })
    if (result.ok) {
      setDraft("")
    } else {
      setSendError(result.error)
    }
  }, [userId, draft, displayName, disabled])

  return (
    <div className="flex min-h-0 flex-1 flex-col rounded-lg border border-white/10 bg-black/30">
      <div className="border-b border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-gray-500">
        Live chat
      </div>
      <div
        ref={listRef}
        className="min-h-[120px] flex-1 overflow-y-auto px-3 py-2 md:min-h-[200px]"
      >
        {messages.length === 0 ? (
          <p className="text-xs text-gray-500">No messages yet.</p>
        ) : (
          <ul className="space-y-3">
            {messages.map((m) => {
              const profile = profiles.get(m.userId)
              const name = profile?.displayName ?? m.displayName
              return (
                <li key={m.id} className="flex gap-2 text-sm">
                  <ChatAvatar profile={profile} />
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-baseline gap-2">
                      <span className="font-medium text-gray-200">{name}</span>
                      <span className="text-[10px] text-gray-600">
                        {new Date(m.sentAt).toLocaleTimeString([], {
                          hour: "numeric",
                          minute: "2-digit",
                        })}
                      </span>
                    </div>
                    <p className="mt-0.5 break-words text-gray-300">{m.text}</p>
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </div>
      <div className="border-t border-white/10 p-2">
        {sendError ? (
          <p className="mb-1 text-xs text-red-400">{sendError}</p>
        ) : null}
        <div className="flex gap-2">
          <input
            type="text"
            value={draft}
            disabled={disabled || !userId}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                void onSend()
              }
            }}
            placeholder={userId ? "Say something…" : "Sign in to chat"}
            maxLength={500}
            className="min-w-0 flex-1 rounded-lg border border-white/10 bg-black/40 px-3 py-2 text-sm text-white placeholder:text-gray-600 disabled:opacity-50"
          />
          <button
            type="button"
            disabled={disabled || !userId || !draft.trim()}
            onClick={() => void onSend()}
            className="shrink-0 rounded-lg bg-white/10 px-3 py-2 text-xs font-semibold text-white hover:bg-white/15 disabled:opacity-50"
          >
            Send
          </button>
        </div>
      </div>
    </div>
  )
}
