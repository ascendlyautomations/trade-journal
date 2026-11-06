import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  assertActiveBroadcastSession,
  blockBroadcastSessionParticipant,
  createBroadcastSpeakInvitation,
  dismissBroadcastHand,
  grantBroadcastSpeaker,
  respondBroadcastSpeakInvitation,
  revokeBroadcastSpeaker,
} from "./tradeRoomBroadcastInteractiveState.ts"
import {
  muteLiveKitBroadcastParticipantMicrophone,
  removeLiveKitBroadcastParticipant,
  setLiveKitBroadcastParticipantMic,
} from "./liveKitRoomService.ts"
import { mintLiveKitBroadcastConversationToken } from "./mintLiveKitBroadcastToken.ts"

export type BroadcastModerationAction =
  | "invite_speak"
  | "request_unmute"
  | "mute_speaker"
  | "revoke_speaker"
  | "remove_viewer"
  | "dismiss_hand"

export async function executeBroadcastModeration(
  admin: SupabaseClient<Database>,
  options: {
    actorUserId: string
    roomId: string
    sessionId: string
    targetUserId: string
    action: BroadcastModerationAction
    blockRejoin?: boolean
  }
): Promise<{ ok: true; invitationId?: string } | { ok: false; status: number; error: string }> {
  const session = await assertActiveBroadcastSession(
    admin,
    options.roomId,
    options.sessionId
  )
  if (!session.ok) return session

  if (options.actorUserId !== session.broadcasterUserId) {
    return { ok: false, status: 403, error: "Only the broadcaster can moderate this stream." }
  }

  if (options.targetUserId === options.actorUserId) {
    return { ok: false, status: 400, error: "You cannot moderate yourself." }
  }

  if (options.targetUserId === session.broadcasterUserId) {
    return { ok: false, status: 400, error: "Invalid target participant." }
  }

  switch (options.action) {
    case "dismiss_hand": {
      const r = await dismissBroadcastHand(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
      })
      return r.ok ? { ok: true } : r
    }
    case "invite_speak": {
      const invite = await createBroadcastSpeakInvitation(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
        invitedBy: options.actorUserId,
      })
      if (!invite.ok) return invite
      return { ok: true, invitationId: invite.invitationId }
    }
    case "request_unmute": {
      const invite = await createBroadcastSpeakInvitation(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
        invitedBy: options.actorUserId,
      })
      if (!invite.ok) return invite
      return { ok: true, invitationId: invite.invitationId }
    }
    case "mute_speaker": {
      try {
        await muteLiveKitBroadcastParticipantMicrophone(
          options.roomId,
          options.targetUserId,
          true
        )
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err)
        return { ok: false, status: 503, error: message }
      }
      return { ok: true }
    }
    case "revoke_speaker": {
      const revoked = await revokeBroadcastSpeaker(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
      })
      if (!revoked.ok) return revoked
      try {
        await setLiveKitBroadcastParticipantMic(options.roomId, options.targetUserId, false)
        await muteLiveKitBroadcastParticipantMicrophone(
          options.roomId,
          options.targetUserId,
          true
        )
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err)
        return { ok: false, status: 503, error: message }
      }
      return { ok: true }
    }
    case "remove_viewer": {
      if (options.blockRejoin) {
        const block = await blockBroadcastSessionParticipant(admin, {
          sessionId: options.sessionId,
          targetUserId: options.targetUserId,
          blockedBy: options.actorUserId,
        })
        if (!block.ok) return block
      }
      await dismissBroadcastHand(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
      })
      await revokeBroadcastSpeaker(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
      })
      try {
        await removeLiveKitBroadcastParticipant(options.roomId, options.targetUserId)
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err)
        if (!/not found|does not exist|404/i.test(message)) {
          return { ok: false, status: 503, error: message }
        }
      }
      return { ok: true }
    }
    default:
      return { ok: false, status: 400, error: "Unknown moderation action." }
  }
}

export async function acceptBroadcastSpeakInvitation(
  admin: SupabaseClient<Database>,
  options: {
    userId: string
    invitationId: string
    displayName: string | null
  }
): Promise<
  | { ok: true; token: NonNullable<Awaited<ReturnType<typeof mintLiveKitBroadcastConversationToken>>>; sessionId: string; roomId: string }
  | { ok: false; status: number; error: string }
> {
  const responded = await respondBroadcastSpeakInvitation(admin, {
    invitationId: options.invitationId,
    userId: options.userId,
    accept: true,
  })
  if (!responded.ok) return responded

  const grant = await grantBroadcastSpeaker(admin, {
    sessionId: responded.sessionId,
    targetUserId: options.userId,
    grantedBy: options.userId,
  })
  if (!grant.ok) return grant

  try {
    await setLiveKitBroadcastParticipantMic(responded.roomId, options.userId, true)
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return { ok: false, status: 503, error: message }
  }

  const token = await mintLiveKitBroadcastConversationToken(
    options.userId,
    responded.roomId,
    options.displayName
  )
  if (!token) {
    return { ok: false, status: 503, error: "Could not mint speaker token." }
  }

  return { ok: true, token, sessionId: responded.sessionId, roomId: responded.roomId }
}
