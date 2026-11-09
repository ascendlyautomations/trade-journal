import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import {
  assertActiveBroadcastSession,
  blockBroadcastSessionParticipant,
  createBroadcastSpeakInvitation,
  dismissBroadcastHand,
  grantBroadcastSpeaker,
  loadBroadcastInteractiveProfiles,
  respondBroadcastSpeakInvitation,
  revokeBroadcastSpeaker,
} from "./tradeRoomBroadcastInteractiveState.ts"
import {
  isLiveKitParticipantAbsentError,
  muteLiveKitBroadcastParticipantMicrophone,
  removeLiveKitBroadcastParticipant,
  setLiveKitBroadcastParticipantMic,
  setLiveKitBroadcastParticipantMicWhenConnected,
} from "./liveKitRoomService.ts"
import { liveKitBroadcastRoomName } from "./liveKitRoomName.ts"
import { mintLiveKitBroadcastConversationToken } from "./mintLiveKitBroadcastToken.ts"
import type { TradeRoomBroadcastVideoSource } from "./tradeRoomBroadcastVoiceMode.ts"
import {
  broadcastModerationActionAllowed,
  resolveBroadcastModerationActorAccess,
  resolveBroadcastModerationTargetAccess,
} from "./broadcastModerationAccess.ts"

export type { BroadcastModerationAction } from "./broadcastModerationAccess.ts"
import type { BroadcastModerationAction } from "./broadcastModerationAccess.ts"

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
): Promise<
  | { ok: true; invitationId?: string; targetDisplayName?: string }
  | { ok: false; status: number; error: string; retryable?: boolean }
> {
  const session = await assertActiveBroadcastSession(
    admin,
    options.roomId,
    options.sessionId
  )
  if (!session.ok) return session

  const actor = await resolveBroadcastModerationActorAccess(admin, {
    actorUserId: options.actorUserId,
    roomId: options.roomId,
    sessionId: options.sessionId,
    broadcasterUserId: session.broadcasterUserId,
  })
  if (!actor.ok) return actor

  if (
    !broadcastModerationActionAllowed({
      action: options.action,
      isBroadcaster: actor.isBroadcaster,
      canModerate: actor.canModerate,
      canManage: actor.canManage,
    })
  ) {
    return { ok: false, status: 403, error: "Permission denied." }
  }

  const target = await resolveBroadcastModerationTargetAccess(admin, {
    actorUserId: options.actorUserId,
    roomId: options.roomId,
    targetUserId: options.targetUserId,
    broadcasterUserId: session.broadcasterUserId,
    canManage: actor.canManage,
    canModerate: actor.canModerate,
  })
  if (!target.ok) return target

  switch (options.action) {
    case "dismiss_hand": {
      const r = await dismissBroadcastHand(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
      })
      return r.ok ? { ok: true } : r
    }
    case "invite_speak": {
      const profiles = await loadBroadcastInteractiveProfiles(admin, [
        options.targetUserId,
      ])
      const targetProfile = profiles.get(options.targetUserId)
      const targetDisplayName =
        targetProfile?.displayName?.trim() ||
        targetProfile?.username?.trim() ||
        "Member"

      const grant = await grantBroadcastSpeaker(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
        grantedBy: options.actorUserId,
      })
      if (!grant.ok) return grant

      await dismissBroadcastHand(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
      })

      try {
        await setLiveKitBroadcastParticipantMic(
          options.roomId,
          options.targetUserId,
          true
        )
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err)
        if (!isLiveKitParticipantAbsentError(message)) {
          return { ok: false, status: 503, error: message }
        }
      }

      const invite = await createBroadcastSpeakInvitation(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
        invitedBy: options.actorUserId,
      })
      if (!invite.ok) {
        return invite
      }

      return { ok: true, targetDisplayName, invitationId: invite.invitationId }
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
      const tryRemoveFromLiveKit = async (): Promise<
        | { ok: true }
        | { ok: false; status: number; error: string; retryable?: boolean }
      > => {
        const absent = (message: string) =>
          /not found|does not exist|404/i.test(message)
        try {
          await removeLiveKitBroadcastParticipant(
            options.roomId,
            options.targetUserId
          )
          return { ok: true }
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err)
          if (absent(message)) {
            return { ok: true }
          }
        }
        try {
          await removeLiveKitBroadcastParticipant(
            options.roomId,
            options.targetUserId
          )
          return { ok: true }
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err)
          if (absent(message)) {
            return { ok: true }
          }
          return {
            ok: false,
            status: 503,
            error:
              "Could not disconnect the participant from LiveKit. Try again in a moment.",
            retryable: true,
          }
        }
      }

      const removed = await tryRemoveFromLiveKit()
      if (!removed.ok) {
        return removed
      }

      const dismissed = await dismissBroadcastHand(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
      })
      if (!dismissed.ok) {
        return dismissed
      }

      const revoked = await revokeBroadcastSpeaker(admin, {
        sessionId: options.sessionId,
        targetUserId: options.targetUserId,
      })
      if (!revoked.ok) {
        return revoked
      }

      if (options.blockRejoin) {
        const block = await blockBroadcastSessionParticipant(admin, {
          sessionId: options.sessionId,
          targetUserId: options.targetUserId,
          blockedBy: options.actorUserId,
        })
        if (!block.ok) {
          return block
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
  | {
      ok: true
      token: NonNullable<Awaited<ReturnType<typeof mintLiveKitBroadcastConversationToken>>>
      sessionId: string
      roomId: string
      broadcasterUserId: string
      broadcasterDisplayName: string | null
      startedAt: string
      voiceMode: "broadcast_only" | "open_voice"
      videoSource: TradeRoomBroadcastVideoSource
      broadcastSource: "browser" | "obs"
      primaryMediaPublisherIdentity: string | null
    }
  | { ok: false; status: number; error: string }
> {
  const { data: inviteRow } = await admin
    .from("room_live_broadcast_invitations")
    .select("invited_by")
    .eq("id", options.invitationId)
    .eq("user_id", options.userId)
    .eq("status", "pending")
    .maybeSingle()

  if (!inviteRow) {
    return { ok: false, status: 404, error: "Invitation not found." }
  }

  const responded = await respondBroadcastSpeakInvitation(admin, {
    invitationId: options.invitationId,
    userId: options.userId,
    accept: true,
  })
  if (!responded.ok) return responded

  const grantedBy =
    typeof inviteRow.invited_by === "string" && inviteRow.invited_by.trim()
      ? inviteRow.invited_by.trim()
      : responded.broadcasterUserId

  const grant = await grantBroadcastSpeaker(admin, {
    sessionId: responded.sessionId,
    targetUserId: options.userId,
    grantedBy,
  })
  if (!grant.ok) return grant

  let micUpdate: Awaited<
    ReturnType<typeof setLiveKitBroadcastParticipantMicWhenConnected>
  >
  try {
    micUpdate = await setLiveKitBroadcastParticipantMicWhenConnected(
      responded.roomId,
      options.userId,
      true
    )
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error("[livekit/broadcast/invite-respond] accept mic update failed", {
      endpoint: "POST /api/livekit/broadcast/invite/respond",
      httpStatus: 503,
      broadcastSessionId: responded.sessionId,
      roomId: responded.roomId,
      livekitRoom: liveKitBroadcastRoomName(responded.roomId),
      viewerUserId: options.userId,
      livekitIdentity: options.userId,
      participantInRoom: null,
      tokenMinted: false,
      error: message,
    })
    return { ok: false, status: 503, error: message }
  }

  console.info("[livekit/broadcast/invite-respond] accept mic permissions", {
    endpoint: "POST /api/livekit/broadcast/invite/respond",
    broadcastSessionId: responded.sessionId,
    roomId: responded.roomId,
    livekitRoom: micUpdate.livekitRoom,
    viewerUserId: options.userId,
    livekitIdentity: options.userId,
    participantInRoom: micUpdate.attempted,
    skippedAbsentParticipant: micUpdate.skippedAbsent,
  })

  const token = await mintLiveKitBroadcastConversationToken(
    options.userId,
    responded.roomId,
    options.displayName
  )
  if (!token) {
    console.error("[livekit/broadcast/invite-respond] accept token mint failed", {
      endpoint: "POST /api/livekit/broadcast/invite/respond",
      httpStatus: 503,
      broadcastSessionId: responded.sessionId,
      roomId: responded.roomId,
      livekitRoom: liveKitBroadcastRoomName(responded.roomId),
      viewerUserId: options.userId,
      livekitIdentity: options.userId,
      participantInRoom: micUpdate.attempted,
      tokenMinted: false,
    })
    return { ok: false, status: 503, error: "Could not mint speaker token." }
  }

  console.info("[livekit/broadcast/invite-respond] accept token minted", {
    endpoint: "POST /api/livekit/broadcast/invite/respond",
    httpStatus: 200,
    broadcastSessionId: responded.sessionId,
    roomId: responded.roomId,
    livekitRoom: token.roomName,
    viewerUserId: options.userId,
    livekitIdentity: options.userId,
    participantInRoom: micUpdate.attempted,
    tokenMinted: true,
    role: token.role,
    canPublish: token.canPublish,
  })

  return {
    ok: true,
    token,
    sessionId: responded.sessionId,
    roomId: responded.roomId,
    broadcasterUserId: responded.broadcasterUserId,
    broadcasterDisplayName: responded.broadcasterDisplayName,
    startedAt: responded.startedAt,
    voiceMode: responded.voiceMode,
    videoSource: responded.videoSource,
    broadcastSource: responded.broadcastSource,
    primaryMediaPublisherIdentity: responded.primaryMediaPublisherIdentity,
  }
}
