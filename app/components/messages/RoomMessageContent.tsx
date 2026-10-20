"use client"

import VoiceMessageBubble from "@/app/components/messages/VoiceMessageBubble"
import RoomSharedContentCard from "@/app/components/messages/RoomSharedContentCard"
import StoryShareMessageCard from "@/app/components/messages/StoryShareMessageCard"
import StorageImage from "@/app/components/ui/StorageImage"
import SyncStatusText from "@/app/components/ui/SyncStatusText"
import { isVoiceMessage } from "@/lib/voiceMessage"
import {
  resolveRoomMessageShare,
  roomMessageDisplayText,
} from "@/lib/roomMessageSharedContent"
import { resolveStorySharePayload } from "@/lib/storyShareMessage"
import { canEditRoomMessage } from "@/lib/roomModeration"

export type RoomMessageContentMessage = {
  id: string
  user_id: string
  type?: string | null
  content: string
  image_url?: string | null
  audio_url?: string | null
  audio_duration_ms?: number | null
  trade_id?: string | null
  trades?: { id?: string } | null
  send_status?: "sending" | "sent" | "failed" | null
}

type RoomMessageContentProps = {
  msg: RoomMessageContentMessage
  viewerUserId?: string | null
  nativeIos?: boolean
  editingMessageId: string | null
  editingMessageContent: string
  setEditingMessageContent: (value: string) => void
  onSaveEdit: (messageId: string) => void
  onCancelEdit: () => void
  onViewTrade: (trade: { id?: string | null }) => void
  onViewStory: (storyId: string) => void
  onNavigate: (href: string) => void
  setLightboxImageUrl: (url: string | null) => void
  onRetryFailed?: () => void
}

export default function RoomMessageContent({
  msg,
  viewerUserId,
  nativeIos = false,
  editingMessageId,
  editingMessageContent,
  setEditingMessageContent,
  onSaveEdit,
  onCancelEdit,
  onViewTrade,
  onViewStory,
  onNavigate,
  setLightboxImageUrl,
  onRetryFailed,
}: RoomMessageContentProps) {
  const share = resolveRoomMessageShare(msg)
  const caption = roomMessageDisplayText(msg)
  const storyPayload = resolveStorySharePayload(msg)

  return (
    <div className="text-sm">
      {msg.type === "image" ? (
        <>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              if (msg.image_url) {
                setLightboxImageUrl(msg.image_url)
              }
            }}
            className="mt-1 block max-w-full cursor-zoom-in"
            aria-label="View image full screen"
          >
            <StorageImage
              src={msg.image_url}
              originalSrc={msg.image_url}
              preset="message-preview"
              fallbackToOriginal={false}
              intrinsicWidth={640}
              className="max-w-xs rounded"
              alt=""
            />
          </button>
          {caption ? (
            <p className="mt-2 whitespace-pre-wrap break-words text-sm text-white">
              {caption}
            </p>
          ) : null}
        </>
      ) : msg.type === "voice" || isVoiceMessage(msg) ? (
        msg.audio_url ? (
          <VoiceMessageBubble
            messageId={String(msg.id)}
            audioUrl={msg.audio_url}
            durationMs={msg.audio_duration_ms}
            isOutgoing={msg.user_id === viewerUserId}
          />
        ) : (
          <p className="text-xs text-gray-400">Sending voice message…</p>
        )
      ) : storyPayload ? (
        <StoryShareMessageCard
          payload={storyPayload}
          isOutgoing={msg.user_id === viewerUserId}
          onViewStory={onViewStory}
        />
      ) : share ? (
        <>
          <RoomSharedContentCard
            reference={share}
            viewerUserId={viewerUserId}
            onViewTrade={onViewTrade}
            onNavigate={onNavigate}
            deferUntilVisible
            className={nativeIos ? "w-full max-w-full" : undefined}
          />
          {caption ? (
            <p className="mt-2 whitespace-pre-wrap break-words text-sm text-white">
              {caption}
            </p>
          ) : null}
        </>
      ) : editingMessageId === msg.id &&
        canEditRoomMessage(viewerUserId, msg) ? (
        <div className="space-y-2">
          <textarea
            value={editingMessageContent}
            onChange={(e) => setEditingMessageContent(e.target.value)}
            rows={3}
            className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-blue-400/40"
          />
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => onSaveEdit(msg.id)}
              disabled={!editingMessageContent.trim()}
              className="rounded-lg bg-blue-500 px-3 py-1 text-xs text-white hover:bg-blue-600 disabled:opacity-50 disabled:hover:bg-blue-500"
            >
              Save
            </button>
            <button
              type="button"
              onClick={onCancelEdit}
              className="rounded-md px-3 py-1 text-xs text-gray-400 hover:text-white"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : caption ? (
        <p className="whitespace-pre-wrap break-words text-sm text-white">
          {caption}
        </p>
      ) : null}

      {msg.send_status === "sending" || msg.send_status === "failed" ? (
        <SyncStatusText
          status={msg.send_status}
          align="left"
          onRetry={msg.send_status === "failed" ? onRetryFailed : undefined}
        />
      ) : null}
    </div>
  )
}
