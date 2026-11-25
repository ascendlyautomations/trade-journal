"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabaseClient.ts"
import { SafeProfileAvatar } from "@/app/components/SafeProfileAvatar.tsx"
import SharedTradeMessageCard from "@/app/components/SharedTradeMessageCard.tsx"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import { getSharedTradeViewHref } from "@/lib/sharedContentNavigation"
import {
  getTradeRoomBroadcastRoom,
  sendTradeRoomBroadcastChatMessage,
  toggleTradeRoomBroadcastChatReaction,
  type BroadcastInteractiveProfileLite,
} from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"
import type {
  BroadcastChatMessage,
  BroadcastChatReplyReference,
} from "@/lib/livekit/client/tradeRoomBroadcastChat.ts"
import type { BroadcastChatReactionRow } from "@/lib/livekit/client/tradeRoomBroadcastChatReaction.ts"
import {
  peekBroadcastChatProfile,
  resolveBroadcastChatProfiles,
  normalizeBroadcastChatAvatarUrl,
  seedBroadcastChatProfile,
  type BroadcastChatProfile,
} from "@/lib/livekit/client/tradeRoomBroadcastChatProfiles.ts"
import BroadcastChatMessageReactionBadges from "@/app/components/tradeRooms/live/BroadcastChatMessageReactionBadges.tsx"
import BroadcastChatMessageActionSheet from "@/app/components/tradeRooms/live/BroadcastChatMessageActionSheet.tsx"
import { useRoomMessageOpenActions } from "@/app/components/mobile/tradeRooms/roomMessageMobileActions"

type Props = {
  messages: BroadcastChatMessage[]
  chatMessageReactions: BroadcastChatReactionRow[]
  userId: string | null
  displayName: string
  avatarUrl: string | null
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

function replyPreviewText(text: string): string {
  const trimmed = text.trim()
  if (trimmed.length <= 100) return trimmed
  return `${trimmed.slice(0, 100)}…`
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

function BroadcastChatMessageBody({
  message,
  viewerUserId,
  reactions,
  canReact,
  onExpandImage,
  onViewTrade,
  onToggleReaction,
}: {
  message: BroadcastChatMessage
  viewerUserId: string | null
  reactions: BroadcastChatReactionRow[]
  canReact: boolean
  onExpandImage: (url: string) => void
  onViewTrade: (tradeId: string) => void
  onToggleReaction?: (emoji: string) => void
}) {
  return (
    <div className="mt-0.5 space-y-1">
      {message.replyTo ? (
        <div className="border-l-2 border-violet-400/70 pl-2 text-[10px] text-gray-500">
          <span className="font-semibold text-violet-300/90">
            {message.replyTo.displayName}
          </span>
          <span className="ml-1">{message.replyTo.textPreview}</span>
        </div>
      ) : null}
      {message.imageUrl ? (
        <button
          type="button"
          className="block max-w-[160px] overflow-hidden rounded-lg border border-white/10 bg-black/20"
          onClick={() => onExpandImage(message.imageUrl!)}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={message.imageUrl}
            alt="Chat attachment"
            className="max-h-[120px] w-full object-contain"
          />
        </button>
      ) : null}
      {message.tradeId ? (
        <SharedTradeMessageCard
          tradeId={message.tradeId}
          viewerUserId={viewerUserId}
          onViewTrade={(trade) => {
            const id = trade?.id != null ? String(trade.id).trim() : ""
            if (id) onViewTrade(id)
          }}
          showSocialLayer={false}
          hideViewTradeAction
          optimizeMessagePreview
          deferUntilVisible={false}
          className="max-w-[200px]"
        />
      ) : null}
      {message.text ? (
        <p className="break-words text-gray-300">{message.text}</p>
      ) : null}
      <BroadcastChatMessageReactionBadges
        reactions={reactions}
        viewerUserId={viewerUserId}
        onToggle={canReact ? onToggleReaction : undefined}
      />
    </div>
  )
}

function BroadcastChatMessageRow({
  message,
  profile,
  viewerUserId,
  reactions,
  canInteract,
  onExpandImage,
  onViewTrade,
  onOpenMenu,
  onToggleReaction,
}: {
  message: BroadcastChatMessage
  profile: BroadcastChatProfile | undefined
  viewerUserId: string | null
  reactions: BroadcastChatReactionRow[]
  canInteract: boolean
  onExpandImage: (url: string) => void
  onViewTrade: (tradeId: string) => void
  onOpenMenu: () => void
  onToggleReaction: (emoji: string) => void
}) {
  const { handlers } = useRoomMessageOpenActions(message.id, () => onOpenMenu(), {
    disabled: !canInteract,
  })
  const name =
    profile?.displayName?.trim() || message.displayName?.trim() || "Member"

  return (
    <li
      className="flex gap-2 text-sm"
      {...handlers}
      onContextMenu={(e) => {
        if (!canInteract) return
        e.preventDefault()
        onOpenMenu()
      }}
    >
      <ChatAvatar
        profile={profile}
        messageAvatarUrl={message.avatarUrl}
        displayNameForInitial={name}
      />
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-2">
          <span className="font-medium text-gray-200">{name}</span>
          <span className="text-[10px] text-gray-600">
            {new Date(message.sentAt).toLocaleTimeString([], {
              hour: "numeric",
              minute: "2-digit",
            })}
          </span>
        </div>
        <BroadcastChatMessageBody
          message={message}
          viewerUserId={viewerUserId}
          reactions={reactions}
          canReact={canInteract}
          onExpandImage={onExpandImage}
          onViewTrade={onViewTrade}
          onToggleReaction={onToggleReaction}
        />
      </div>
    </li>
  )
}

export default function TradeRoomBroadcastLiveChat({
  messages,
  chatMessageReactions,
  userId,
  displayName,
  avatarUrl,
  disabled,
  interactiveProfiles,
  authLoading,
  className,
}: Props) {
  const router = useRouter()
  const [draft, setDraft] = useState("")
  const [sendError, setSendError] = useState<string | null>(null)
  const [lightboxImageUrl, setLightboxImageUrl] = useState<string | null>(null)
  const [profiles, setProfiles] = useState<Map<string, BroadcastChatProfile>>(
    () => new Map()
  )
  const [activeMenuMessageId, setActiveMenuMessageId] = useState<string | null>(
    null
  )
  const [replyTarget, setReplyTarget] = useState<BroadcastChatMessage | null>(
    null
  )
  const listRef = useRef<HTMLDivElement>(null)

  const reactionsByMessageId = useMemo(() => {
    const map = new Map<string, BroadcastChatReactionRow[]>()
    for (const row of chatMessageReactions) {
      const list = map.get(row.messageId) ?? []
      list.push(row)
      map.set(row.messageId, list)
    }
    return map
  }, [chatMessageReactions])

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

  const scrollSignature = useMemo(
    () =>
      messages
        .map((m) => `${m.id}:${m.imageUrl ?? ""}:${m.tradeId ?? ""}:${m.text.length}`)
        .join("|"),
    [messages]
  )

  useEffect(() => {
    const el = listRef.current
    if (!el) return
    el.scrollTop = el.scrollHeight
  }, [scrollSignature, chatMessageReactions])

  const canInteract = Boolean(userId) && !disabled

  const buildReplyReference = useCallback(
    (message: BroadcastChatMessage): BroadcastChatReplyReference => {
      const profile = mergedByUserId.get(message.userId)
      const name =
        profile?.displayName?.trim() || message.displayName?.trim() || "Member"
      const preview =
        message.text.trim() ||
        (message.imageUrl ? "Photo" : message.tradeId ? "Shared trade" : "Message")
      return {
        messageId: message.id,
        userId: message.userId,
        displayName: name,
        textPreview: replyPreviewText(preview),
      }
    },
    [mergedByUserId]
  )

  const onSend = useCallback(async () => {
    if (!userId || !draft.trim() || disabled) return
    if (!getTradeRoomBroadcastRoom()) {
      setSendError("Not connected to chat.")
      return
    }
    setSendError(null)
    const verified = peekBroadcastChatProfile(userId)
    const replyTo = replyTarget ? buildReplyReference(replyTarget) : null
    const result = await sendTradeRoomBroadcastChatMessage({
      userId,
      displayName: verified?.displayName ?? displayName,
      avatarUrl:
        verified?.avatarUrl ?? normalizeBroadcastChatAvatarUrl(avatarUrl),
      text: draft.trim(),
      replyTo,
    })
    if (result.ok) {
      setDraft("")
      setReplyTarget(null)
    } else {
      setSendError(result.error)
    }
  }, [
    userId,
    draft,
    displayName,
    disabled,
    avatarUrl,
    replyTarget,
    buildReplyReference,
  ])

  const viewSharedTrade = useCallback(
    (tradeId: string) => {
      router.push(getSharedTradeViewHref(tradeId))
    },
    [router]
  )

  const activeMenuMessage = activeMenuMessageId
    ? messages.find((m) => m.id === activeMenuMessageId)
    : null

  const toggleReaction = useCallback(
    (messageId: string, emoji: string) => {
      if (!userId || disabled) return
      void toggleTradeRoomBroadcastChatReaction({ userId, messageId, emoji })
    },
    [userId, disabled]
  )

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
            {messages.map((m) => (
              <BroadcastChatMessageRow
                key={m.id}
                message={m}
                profile={mergedByUserId.get(m.userId)}
                viewerUserId={userId}
                reactions={reactionsByMessageId.get(m.id) ?? []}
                canInteract={canInteract}
                onExpandImage={setLightboxImageUrl}
                onViewTrade={viewSharedTrade}
                onOpenMenu={() => setActiveMenuMessageId(m.id)}
                onToggleReaction={(emoji) => toggleReaction(m.id, emoji)}
              />
            ))}
          </ul>
        )}
      </div>
      {replyTarget ? (
        <div className="flex items-start gap-2 border-t border-white/10 bg-white/5 px-3 py-2 text-xs text-gray-400">
          <div className="min-w-0 flex-1 border-l-2 border-violet-400/60 pl-2">
            <p className="font-semibold text-violet-300/90">
              Reply to {mergedByUserId.get(replyTarget.userId)?.displayName ?? replyTarget.displayName}
            </p>
            <p className="truncate text-gray-500">
              {replyPreviewText(
                replyTarget.text.trim() ||
                  (replyTarget.imageUrl ? "Photo" : replyTarget.tradeId ? "Shared trade" : "")
              )}
            </p>
          </div>
          <button
            type="button"
            className="shrink-0 text-gray-500 hover:text-white"
            onClick={() => setReplyTarget(null)}
          >
            ✕
          </button>
        </div>
      ) : null}
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
      {lightboxImageUrl ? (
        <ImageLightbox
          imageUrl={lightboxImageUrl}
          onClose={() => setLightboxImageUrl(null)}
        />
      ) : null}
      <BroadcastChatMessageActionSheet
        open={activeMenuMessage != null}
        onClose={() => setActiveMenuMessageId(null)}
        canReply={canInteract}
        canReact={canInteract}
        onReply={() => {
          if (activeMenuMessage) setReplyTarget(activeMenuMessage)
        }}
        onSelectReaction={(emoji) => {
          if (activeMenuMessage) toggleReaction(activeMenuMessage.id, emoji)
        }}
      />
    </div>
  )
}