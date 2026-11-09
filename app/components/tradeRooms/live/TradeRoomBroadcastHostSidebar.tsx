"use client"

import { useEffect, useState } from "react"
import { SafeProfileAvatar } from "@/app/components/SafeProfileAvatar.tsx"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import TradeRoomBroadcastLiveChat from "./TradeRoomBroadcastLiveChat.tsx"
import TradeRoomLiveParticipantModerationMenu from "./TradeRoomLiveParticipantModerationMenu.tsx"
import TradeRoomLiveModerationErrorNote from "./TradeRoomLiveModerationErrorNote.tsx"
import { postBroadcastModeration } from "./tradeRoomBroadcastModerationClient.ts"
import { refreshBroadcastInteractiveState } from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"

function profileLabel(
  userId: string,
  profiles: Record<
    string,
    { displayName: string; username: string | null; avatarUrl?: string | null }
  >
): string {
  const profile = profiles[userId]
  return profile?.displayName || profile?.username || "Member"
}

function sidebarAvatarInitial(name: string): string {
  const t = name.trim()
  return (t.charAt(0) || "?").toUpperCase()
}

type ChatProps = {
  userId: string | null
  displayName: string
  avatarUrl: string | null
  disabled?: boolean
  authLoading?: boolean
}

type Props = {
  accessToken: string
  className?: string
  /** Host: participants / hands / chat. Viewer theater: chat + participants only. */
  sidebarLayout?: "host" | "viewer"
  chat: ChatProps
  isBroadcaster: boolean
  canModerateStream: boolean
  /** LiveKit roster required for participant-level stream moderation (mods must be watching). */
  canModerateLiveParticipants: boolean
  canActOnTarget: (targetUserId: string) => boolean
  onModerationMessage?: (text: string) => void | Promise<void>
}

export default function TradeRoomBroadcastHostSidebar({
  accessToken,
  className,
  sidebarLayout = "host",
  chat,
  isBroadcaster,
  canModerateStream,
  canModerateLiveParticipants,
  canActOnTarget,
  onModerationMessage,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const [sidebarTab, setSidebarTab] = useState<"participants" | "hands" | "chat">(
    "chat"
  )
  const viewerTabs = ["chat", "participants"] as const
  const hostTabs = ["participants", "hands", "chat"] as const
  const [busyUserId, setBusyUserId] = useState<string | null>(null)
  const [moderationError, setModerationError] = useState<string | null>(null)

  const sessionId = broadcast.status.broadcastSessionId
  const roomId = broadcast.roomId

  useEffect(() => {
    if (!canModerateStream || canModerateLiveParticipants) return
    if (broadcast.raisedHandIdentities.length > 0) {
      setSidebarTab("hands")
    }
  }, [
    canModerateStream,
    canModerateLiveParticipants,
    broadcast.raisedHandIdentities.length,
  ])

  const afterModeration = () => {
    void refreshBroadcastInteractiveState(accessToken)
  }

  const reportModerationError = (message: string) => {
    setModerationError(message)
  }

  const inviteToSpeak = async (targetUserId: string) => {
    if (!roomId || !sessionId) return
    const name = profileLabel(targetUserId, broadcast.interactiveProfiles)
    setBusyUserId(targetUserId)
    try {
      const result = await postBroadcastModeration(accessToken, {
        roomId,
        sessionId,
        targetUserId,
        action: "invite_speak",
      })
      if (!result.ok) {
        reportModerationError(result.error)
        return
      }
      setModerationError(null)
      if (onModerationMessage) {
        await onModerationMessage(`${name} got permission to speak.`)
      }
      afterModeration()
    } finally {
      setBusyUserId(null)
    }
  }

  const showModMenu = (targetUserId: string) =>
    Boolean(
      roomId &&
        sessionId &&
        canModerateStream &&
        canActOnTarget(targetUserId)
    )

  const showParticipantModMenu = (targetUserId: string) =>
    canModerateLiveParticipants && showModMenu(targetUserId)

  const body = (
    <>
      {sidebarTab === "hands" ? (
        broadcast.raisedHandIdentities.length === 0 ? (
          <p className="text-white/60">No raised hands yet.</p>
        ) : (
          <ul className="space-y-2">
            {broadcast.raisedHandIdentities.map((id) => {
              const label = profileLabel(id, broadcast.interactiveProfiles)
              return (
                <li
                  key={id}
                  className="flex items-center justify-between gap-2 rounded-lg bg-white/5 px-2 py-2"
                >
                  <div className="flex min-w-0 flex-1 items-center gap-2">
                    <SafeProfileAvatar
                      src={broadcast.interactiveProfiles[id]?.avatarUrl ?? null}
                      alt=""
                      displaySizePx={64}
                      className="h-8 w-8 shrink-0"
                      fallback={
                        <span className="flex h-full w-full items-center justify-center bg-white/10 text-xs font-semibold text-gray-300">
                          {sidebarAvatarInitial(label)}
                        </span>
                      }
                    />
                    <span className="min-w-0 truncate font-medium">{label}</span>
                  </div>
                  <div className="flex shrink-0 items-center gap-1">
                    {isBroadcaster ? (
                      <button
                        type="button"
                        disabled={busyUserId === id}
                        className="text-xs font-semibold text-emerald-300 disabled:opacity-50"
                        onClick={() => void inviteToSpeak(id)}
                      >
                        {busyUserId === id ? "Inviting…" : "Invite"}
                      </button>
                    ) : null}
                    {showModMenu(id) ? (
                      <TradeRoomLiveParticipantModerationMenu
                        surface="broadcast-hand"
                        roomId={roomId!}
                        sessionId={sessionId!}
                        accessToken={accessToken}
                        targetUserId={id}
                        targetDisplayName={label}
                        isBroadcaster={isBroadcaster}
                        onDone={afterModeration}
                        onError={reportModerationError}
                        onSuccess={() => setModerationError(null)}
                      />
                    ) : null}
                  </div>
                </li>
              )
            })}
          </ul>
        )
      ) : sidebarTab === "chat" ? (
        <TradeRoomBroadcastLiveChat
          className="h-full min-h-0"
          messages={broadcast.chatMessages}
          userId={chat.userId}
          displayName={chat.displayName}
          avatarUrl={chat.avatarUrl}
          interactiveProfiles={broadcast.interactiveProfiles}
          disabled={chat.disabled}
          authLoading={chat.authLoading}
        />
      ) : !canModerateLiveParticipants && canModerateStream && !isBroadcaster ? (
        <p className="text-white/70">
          Join the livestream to manage participants. You can still review raised
          hands on the Hands tab.
        </p>
      ) : broadcast.liveParticipants.length === 0 ? (
        <p className="text-white/60">Waiting for viewers to join…</p>
      ) : (
        <ul className="space-y-2">
          {broadcast.liveParticipants.map((p) => {
            const label = p.displayName || profileLabel(p.userId, broadcast.interactiveProfiles)
            if (p.isBroadcaster) {
              return (
                <li
                  key={p.userId}
                  className="flex items-center gap-2 rounded-lg bg-white/5 px-2 py-2 text-sm"
                >
                  <SafeProfileAvatar
                    src={broadcast.interactiveProfiles[p.userId]?.avatarUrl ?? null}
                    alt=""
                    displaySizePx={64}
                    className="h-8 w-8 shrink-0"
                    fallback={
                      <span className="flex h-full w-full items-center justify-center bg-white/10 text-xs font-semibold text-gray-300">
                        {sidebarAvatarInitial(label)}
                      </span>
                    }
                  />
                  <div className="min-w-0 flex-1">
                    <span className="font-medium">{label}</span>
                    <span className="ml-2 text-[10px] uppercase text-red-300">
                      Host
                    </span>
                  </div>
                </li>
              )
            }
            const isSpeaker = broadcast.speakerGrantUserIds.includes(p.userId)
            const blocked = broadcast.sessionBlockUserIds.includes(p.userId)
            return (
              <li
                key={p.userId}
                className="flex items-center gap-2 rounded-lg bg-white/5 px-2 py-2 text-sm"
              >
                <SafeProfileAvatar
                  src={broadcast.interactiveProfiles[p.userId]?.avatarUrl ?? null}
                  alt=""
                  displaySizePx={64}
                  className="h-8 w-8 shrink-0"
                  fallback={
                    <span className="flex h-full w-full items-center justify-center bg-white/10 text-xs font-semibold text-gray-300">
                      {sidebarAvatarInitial(label)}
                    </span>
                  }
                />
                <div className="min-w-0 flex-1">
                  <span className="min-w-0 truncate font-medium">{label}</span>
                  {isSpeaker ? (
                    <span className="ml-2 text-[10px] uppercase text-emerald-300">
                      Speaker
                    </span>
                  ) : null}
                  {blocked ? (
                    <span className="ml-2 text-[10px] uppercase text-red-400">
                      Blocked
                    </span>
                  ) : null}
                </div>
                {showParticipantModMenu(p.userId) ? (
                  <TradeRoomLiveParticipantModerationMenu
                    surface="broadcast-participant"
                    roomId={roomId!}
                    sessionId={sessionId!}
                    accessToken={accessToken}
                    targetUserId={p.userId}
                    targetDisplayName={label}
                    isBroadcaster={isBroadcaster}
                    isSpeaker={isSpeaker}
                    onDone={afterModeration}
                    onBroadcastChatLine={onModerationMessage}
                    onError={reportModerationError}
                    onSuccess={() => setModerationError(null)}
                  />
                ) : null}
              </li>
            )
          })}
        </ul>
      )}
    </>
  )

  return (
    <aside
      className={`flex h-full min-h-0 flex-col overflow-hidden rounded-xl border border-white/10 bg-zinc-900/40 ${className ?? ""}`}
    >
      <div
        className={`grid shrink-0 border-b border-white/10 text-xs ${
          sidebarLayout === "viewer" ? "grid-cols-2" : "grid-cols-3"
        }`}
      >
        {(sidebarLayout === "viewer" ? viewerTabs : hostTabs).map((tab) => (
          <button
            key={tab}
            type="button"
            className={`px-2 py-2 capitalize ${sidebarTab === tab ? "bg-white/10" : ""}`}
            onClick={() => setSidebarTab(tab)}
          >
            {tab}
            {tab === "hands" ? ` (${broadcast.raisedHandIdentities.length})` : ""}
            {tab === "participants" ? ` (${broadcast.liveParticipants.length})` : ""}
          </button>
        ))}
      </div>
      <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-hidden p-3 text-sm text-white">
        <TradeRoomLiveModerationErrorNote
          message={moderationError}
          onDismiss={() => setModerationError(null)}
        />
        <div className="flex min-h-0 flex-1 flex-col overflow-hidden">{body}</div>
      </div>
    </aside>
  )
}
