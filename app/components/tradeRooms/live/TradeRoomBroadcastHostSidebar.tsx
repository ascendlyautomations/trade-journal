"use client"

import { useState } from "react"
import { useTradeRoomBroadcast } from "./useTradeRoomBroadcast.ts"
import TradeRoomBroadcastLiveChat from "./TradeRoomBroadcastLiveChat.tsx"
import { postBroadcastModeration } from "./tradeRoomBroadcastModerationClient.ts"
import { refreshBroadcastInteractiveState } from "@/lib/livekit/client/tradeRoomBroadcastStore.ts"

function profileLabel(
  userId: string,
  profiles: Record<string, { displayName: string; username: string | null }>
): string {
  const profile = profiles[userId]
  return profile?.displayName || profile?.username || "Member"
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
  chat: ChatProps
  onModerationMessage?: (text: string) => void | Promise<void>
}

export default function TradeRoomBroadcastHostSidebar({
  accessToken,
  className,
  chat,
  onModerationMessage,
}: Props) {
  const broadcast = useTradeRoomBroadcast()
  const [sidebarTab, setSidebarTab] = useState<"participants" | "hands" | "chat">(
    "chat"
  )
  const [busyUserId, setBusyUserId] = useState<string | null>(null)

  const sessionId = broadcast.status.broadcastSessionId
  const roomId = broadcast.roomId

  const runModeration = async (
    targetUserId: string,
    action: Parameters<typeof postBroadcastModeration>[1]["action"],
    options?: { blockRejoin?: boolean; chatLine?: string }
  ) => {
    if (!roomId || !sessionId) return
    setBusyUserId(targetUserId)
    try {
      const result = await postBroadcastModeration(accessToken, {
        roomId,
        sessionId,
        targetUserId,
        action,
        blockRejoin: options?.blockRejoin,
      })
      if (!result.ok) {
        console.warn("[broadcast] moderation failed", result.error)
        return
      }
      if (options?.chatLine && onModerationMessage) {
        await onModerationMessage(options.chatLine)
      }
      void refreshBroadcastInteractiveState(accessToken)
    } finally {
      setBusyUserId(null)
    }
  }

  const inviteToSpeak = async (targetUserId: string) => {
    const name = profileLabel(targetUserId, broadcast.interactiveProfiles)
    await runModeration(targetUserId, "invite_speak", {
      chatLine: `${name} got permission to speak.`,
    })
  }

  const body = (
    <>
      {sidebarTab === "hands" ? (
        broadcast.raisedHandIdentities.length === 0 ? (
          <p className="text-white/60">No raised hands yet.</p>
        ) : (
          <ul className="space-y-2">
            {broadcast.raisedHandIdentities.map((id) => (
              <li
                key={id}
                className="flex items-center justify-between gap-2 rounded-lg bg-white/5 px-2 py-2"
              >
                <span className="min-w-0 truncate font-medium">
                  {profileLabel(id, broadcast.interactiveProfiles)}
                </span>
                <button
                  type="button"
                  disabled={busyUserId === id}
                  className="shrink-0 text-xs font-semibold text-emerald-300 disabled:opacity-50"
                  onClick={() => void inviteToSpeak(id)}
                >
                  {busyUserId === id ? "Inviting…" : "Invite to speak"}
                </button>
              </li>
            ))}
          </ul>
        )
      ) : sidebarTab === "chat" ? (
        <TradeRoomBroadcastLiveChat
          className="h-full min-h-0"
          messages={broadcast.chatMessages}
          userId={chat.userId}
          displayName={chat.displayName}
          avatarUrl={chat.avatarUrl}
          disabled={chat.disabled}
          authLoading={chat.authLoading}
        />
      ) : broadcast.liveParticipants.length === 0 ? (
        <p className="text-white/60">Waiting for viewers to join…</p>
      ) : (
        <ul className="space-y-2">
          {broadcast.liveParticipants.map((p) => {
            if (p.isBroadcaster) {
              return (
                <li
                  key={p.userId}
                  className="rounded-lg bg-white/5 px-2 py-2 text-sm"
                >
                  <span className="font-medium">{p.displayName}</span>
                  <span className="ml-2 text-[10px] uppercase text-red-300">Host</span>
                </li>
              )
            }
            const isSpeaker = broadcast.speakerGrantUserIds.includes(p.userId)
            const blocked = broadcast.sessionBlockUserIds.includes(p.userId)
            return (
              <li
                key={p.userId}
                className="rounded-lg bg-white/5 px-2 py-2 text-sm"
              >
                <div className="flex min-w-0 items-center justify-between gap-2">
                  <span className="min-w-0 truncate font-medium">{p.displayName}</span>
                  {isSpeaker ? (
                    <span className="shrink-0 text-[10px] uppercase text-emerald-300">
                      Speaker
                    </span>
                  ) : null}
                  {blocked ? (
                    <span className="shrink-0 text-[10px] uppercase text-red-400">
                      Blocked
                    </span>
                  ) : null}
                </div>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {!isSpeaker ? (
                    <button
                      type="button"
                      disabled={busyUserId === p.userId}
                      className="rounded bg-emerald-600/80 px-2 py-1 text-[11px] font-semibold text-white disabled:opacity-50"
                      onClick={() => void inviteToSpeak(p.userId)}
                    >
                      Invite
                    </button>
                  ) : (
                    <>
                      <button
                        type="button"
                        disabled={busyUserId === p.userId}
                        className="rounded bg-white/10 px-2 py-1 text-[11px] disabled:opacity-50"
                        onClick={() =>
                          void runModeration(p.userId, "mute_speaker")
                        }
                      >
                        Mute
                      </button>
                      <button
                        type="button"
                        disabled={busyUserId === p.userId}
                        className="rounded bg-white/10 px-2 py-1 text-[11px] disabled:opacity-50"
                        onClick={() =>
                          void runModeration(p.userId, "revoke_speaker", {
                            chatLine: `${p.displayName} is no longer a speaker.`,
                          })
                        }
                      >
                        Revoke
                      </button>
                    </>
                  )}
                  <button
                    type="button"
                    disabled={busyUserId === p.userId}
                    className="rounded bg-white/10 px-2 py-1 text-[11px] disabled:opacity-50"
                    onClick={() =>
                      void runModeration(p.userId, "remove_viewer", {
                        chatLine: `${p.displayName} was removed from the stream.`,
                      })
                    }
                  >
                    Remove
                  </button>
                  <button
                    type="button"
                    disabled={busyUserId === p.userId}
                    className="rounded bg-red-600/80 px-2 py-1 text-[11px] font-semibold text-white disabled:opacity-50"
                    onClick={() =>
                      void runModeration(p.userId, "remove_viewer", {
                        blockRejoin: true,
                        chatLine: `${p.displayName} was removed and blocked for this stream.`,
                      })
                    }
                  >
                    Remove &amp; block
                  </button>
                </div>
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
      <div className="grid shrink-0 grid-cols-3 border-b border-white/10 text-xs">
        {(["participants", "hands", "chat"] as const).map((tab) => (
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
      <div className="flex min-h-0 flex-1 flex-col overflow-hidden p-3 text-sm text-white">
        {body}
      </div>
    </aside>
  )
}
