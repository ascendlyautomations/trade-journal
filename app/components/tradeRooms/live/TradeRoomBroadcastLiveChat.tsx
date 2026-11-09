"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "@/lib/supabaseClient.ts"
import { SafeProfileAvatar } from "@/app/components/SafeProfileAvatar.tsx"
import {
  getTradeRoomBroadcastRoom,
  sendTradeRoomBroadcastChatMessage,
  type BroadcastInteractiveProfileLite,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import type { BroadcastChatMessage } from "@/lib/livekit/client/tradeRoomBroadcastChat.ts"
import {
  peekBroadcastChatProfile,
  resolveBroadcastChatProfiles,
  normalizeBroadcastChatAvatarUrl,
  seedBroadcastChatProfile,
  type BroadcastChatProfile,
} from "@/lib/livekit/client/tradeRoomBroadcastChatProfiles.ts"

type Props = {
  messages: BroadcastChatMessage[]
  userId: string | null
  displayName: string
  avatarUrl: string | null
  /** From API / interactive-state (service role); fills gaps when client profiles IN() returns nothing under RLS. */
  interactiveProfiles?: Record<string, BroadcastInteractiveProfileLite>
  disabled?: boolean
  authLoading?: boolean
  className?: string
}

function mergeChatProfileForUser(args: {
  userId: string
  fetched: BroadcastChatProfile | undefined
  interactive: BroadcastInteractiveProfileLite | undefined
  messageSample: BroadcastChatMessage | undefined
}): BroadcastChatProfile {
  const { userId, fetched, interactive, messageSample } = args
  const displayName =
    fetched?.displayName?.trim() ||
    interactive?.displayName?.trim() ||
    interactive?.username?.trim() ||
    messageSample?.displayName?.trim() ||
    "Member"
  const rawAvatar =
    fetched?.avatarUrl ??
    interactive?.avatarUrl ??
    messageSample?.avatarUrl ??
    null
  return {
    userId,
    displayName,
    avatarUrl: normalizeBroadcastChatAvatarUrl(rawAvatar),
  }
}

function ChatAvatar({
  profile,
  messageAvatarUrl,
  displayNameForInitial,
}: {
  profile: BroadcastChatProfile | undefined
  messageAvatarUrl: string | null
  displayNameForInitial: string
}) {
  const label =
    profile?.displayName?.charAt(0)?.toUpperCase() ??
    displayNameForInitial.charAt(0)?.toUpperCase() ??
    "?"
  const src =
    profile?.avatarUrl ??
    (messageAvatarUrl ? normalizeBroadcastChatAvatarUrl(messageAvatarUrl) : null)
  return (
    <SafeProfileAvatar
      src={src}
      alt=""
      displaySizePx={56}
      className="h-7 w-7 shrink-0"
      fallback={
        <span className="flex h-full w-full items-center justify-center bg-white/10 text-xs font-semibold text-gray-300">
          {label}
        </span>
      }
    />
  )
}

export default function TradeRoomBroadcastLiveChat({
  messages,
  userId,
  displayName,
  avatarUrl,
  disabled,
  interactiveProfiles,
  authLoading,
  className,
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
        avatarUrl: normalizeBroadcastChatAvatarUrl(avatarUrl),
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

  const mergedByUserId = useMemo(() => {
    const unique = [...new Set(messages.map((m) => m.userId))]
    const map = new Map<string, BroadcastChatProfile>()
    const firstMessageByUser = new Map<string, BroadcastChatMessage>()
    for (const m of messages) {
      if (!firstMessageByUser.has(m.userId)) firstMessageByUser.set(m.userId, m)
    }
    for (const id of unique) {
      map.set(
        id,
        mergeChatProfileForUser({
          userId: id,
          fetched: profiles.get(id),
          interactive: interactiveProfiles?.[id],
          messageSample: firstMessageByUser.get(id),
        })
      )
    }
    return map
  }, [messages, profiles, interactiveProfiles])

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
      avatarUrl:
        verified?.avatarUrl ?? normalizeBroadcastChatAvatarUrl(avatarUrl),
      text: draft.trim(),
    })
    if (result.ok) {
      setDraft("")
    } else {
      setSendError(result.error)
    }
  }, [userId, draft, displayName, disabled, avatarUrl])
  return (
    <div
      className={`flex min-h-0 flex-1 flex-col rounded-lg border border-white/10 bg-black/30 ${className ?? ""}`}
    >
      <div className="border-b border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-gray-500">
        Live chat
      </div>
      <div
        ref={listRef}
        className="min-h-0 flex-1 overflow-y-auto px-3 py-2"
      >
        {messages.length === 0 ? (
          <p className="text-xs text-gray-500">No messages yet.</p>
        ) : (
          <ul className="space-y-3">
            {messages.map((m) => {
              const profile = mergedByUserId.get(m.userId)
              const name =
                profile?.displayName?.trim() ||
                m.displayName?.trim() ||
                "Member"
              return (
                <li key={m.id} className="flex gap-2 text-sm">
                  <ChatAvatar
                    profile={profile}
                    messageAvatarUrl={m.avatarUrl}
                    displayNameForInitial={name}
                  />
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
            placeholder={
              userId
                ? "Say something…"
                : authLoading
                  ? "Loading chat…"
                  : "Sign in to chat"
            }
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
