"use client"

import { useMemo, useState } from "react"
import { MoreVertical } from "lucide-react"
import DropdownMenu, { type DropdownMenuItem } from "@/app/components/ui/DropdownMenu.tsx"
import {
  type BroadcastModerationClientAction,
  postBroadcastModeration,
} from "./tradeRoomBroadcastModerationClient.ts"
import {
  demoteStageSpeaker,
  disconnectMemberFromGeneralVoice,
  muteGeneralVoiceParticipant,
  promoteStageSpeaker,
} from "@/lib/livekit/client/tradeRoomLiveModerationClient.ts"

type ModerationCallbacks = {
  onDone?: () => void
  onError?: (message: string) => void
  onSuccess?: () => void
}

type BroadcastMenuProps = ModerationCallbacks & {
  surface: "broadcast-participant" | "broadcast-hand"
  roomId: string
  sessionId: string
  accessToken: string
  targetUserId: string
  targetDisplayName: string
  isBroadcaster: boolean
  isSpeaker?: boolean
  onBroadcastChatLine?: (text: string) => void | Promise<void>
}

type VoiceMenuProps = ModerationCallbacks & {
  surface: "general-voice"
  roomId: string
  accessToken: string
  targetUserId: string
  targetDisplayName: string
  liveVoiceKind: string | null
  isTargetMuted: boolean
}

type Props = BroadcastMenuProps | VoiceMenuProps

function fail(
  callbacks: ModerationCallbacks,
  message: string
) {
  callbacks.onError?.(message)
}

function succeed(callbacks: ModerationCallbacks) {
  callbacks.onSuccess?.()
  callbacks.onDone?.()
}

export default function TradeRoomLiveParticipantModerationMenu(props: Props) {
  const [busy, setBusy] = useState(false)

  const runBroadcast = async (
    action: BroadcastModerationClientAction,
    options?: { blockRejoin?: boolean; chatLine?: string }
  ) => {
    if (props.surface !== "broadcast-participant" && props.surface !== "broadcast-hand") {
      return
    }
    setBusy(true)
    try {
      const result = await postBroadcastModeration(props.accessToken, {
        roomId: props.roomId,
        sessionId: props.sessionId,
        targetUserId: props.targetUserId,
        action,
        blockRejoin: options?.blockRejoin,
      })
      if (!result.ok) {
        fail(props, result.error)
        return
      }
      if (options?.chatLine && props.onBroadcastChatLine) {
        await props.onBroadcastChatLine(options.chatLine)
      }
      succeed(props)
    } finally {
      setBusy(false)
    }
  }

  const runVoiceAction = async (
    label: string,
    action: () => Promise<{ ok: boolean; error?: string }>
  ) => {
    setBusy(true)
    try {
      const result = await action()
      if (!result.ok) {
        fail(props, result.error || `Could not ${label.toLowerCase()}.`)
        return
      }
      succeed(props)
    } finally {
      setBusy(false)
    }
  }

  const items = useMemo((): DropdownMenuItem[] => {
    if (props.surface === "general-voice") {
      const list: DropdownMenuItem[] = []
      const stage = props.liveVoiceKind === "voice_stage"
      if (stage) {
        if (props.isTargetMuted) {
          list.push({
            id: "promote",
            label: "Allow to speak",
            onSelect: () =>
              void runVoiceAction("promote speaker", () =>
                promoteStageSpeaker({
                  roomId: props.roomId,
                  targetUserId: props.targetUserId,
                  accessToken: props.accessToken,
                })
              ),
          })
        } else {
          list.push({
            id: "demote",
            label: "Move to audience",
            onSelect: () =>
              void runVoiceAction("demote speaker", () =>
                demoteStageSpeaker({
                  roomId: props.roomId,
                  targetUserId: props.targetUserId,
                  accessToken: props.accessToken,
                })
              ),
          })
        }
      }
      if (!props.isTargetMuted) {
        list.push({
          id: "mute",
          label: "Force mute",
          onSelect: () =>
            void runVoiceAction("mute", () =>
              muteGeneralVoiceParticipant({
                roomId: props.roomId,
                targetUserId: props.targetUserId,
                accessToken: props.accessToken,
              })
            ),
        })
      }
      list.push({
        id: "disconnect-voice",
        label: "Disconnect from voice",
        variant: "danger",
        onSelect: () =>
          void runVoiceAction("disconnect from voice", () =>
            disconnectMemberFromGeneralVoice({
              roomId: props.roomId,
              userId: props.targetUserId,
              accessToken: props.accessToken,
            })
          ),
      })
      return list
    }

    if (props.surface === "broadcast-hand") {
      return [
        {
          id: "dismiss",
          label: "Dismiss hand",
          onSelect: () => void runBroadcast("dismiss_hand"),
        },
      ]
    }

    const list: DropdownMenuItem[] = []
    const name = props.targetDisplayName.trim() || "Member"
    if (props.isBroadcaster && !props.isSpeaker) {
      list.push({
        id: "invite",
        label: "Invite to speak",
        onSelect: () =>
          void runBroadcast("invite_speak", {
            chatLine: `${name} got permission to speak.`,
          }),
      })
    }
    if (props.isSpeaker) {
      list.push({
        id: "mute",
        label: "Force mute",
        onSelect: () => void runBroadcast("mute_speaker"),
      })
      list.push({
        id: "revoke",
        label: "Revoke speaker",
        onSelect: () =>
          void runBroadcast("revoke_speaker", {
            chatLine: `${name} is no longer a speaker.`,
          }),
      })
    }
    list.push({
      id: "remove",
      label: "Disconnect from stream (can rejoin)",
      variant: "danger",
      onSelect: () =>
        void runBroadcast("remove_viewer", {
          chatLine: `${name} was disconnected from the stream.`,
        }),
    })
    list.push({
      id: "remove-block",
      label: "Remove & block rejoin (this session)",
      variant: "danger",
      onSelect: () =>
        void runBroadcast("remove_viewer", {
          blockRejoin: true,
          chatLine: `${name} was removed and cannot rejoin this session.`,
        }),
    })
    return list
  }, [props, busy])

  if (items.length === 0) {
    return null
  }

  return (
    <DropdownMenu
      align="right"
      disabled={busy}
      ariaLabel="Participant moderation"
      stopPropagation
      trigger={
        <span className="inline-flex rounded-md p-1 text-zinc-400 hover:bg-white/10 hover:text-zinc-100">
          <MoreVertical className="h-4 w-4" aria-hidden />
        </span>
      }
      items={items}
      menuClassName="z-[1200]"
    />
  )
}
