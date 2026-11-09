/**
 * LiveKit participant identity for OBS/Ingress — must not collide with UUID profile ids.
 * Prefix ensures inequality to `broadcaster_user_id` (raw UUID strings).
 */
export const OBS_INGRESS_IDENTITY_PREFIX = "tt-obs-"

export function primaryMediaPublisherIdentityForBroadcastSession(
  broadcastSessionId: string
): string {
  const id = broadcastSessionId.trim()
  if (!id) {
    throw new Error("broadcastSessionId is required for OBS publisher identity.")
  }
  return `${OBS_INGRESS_IDENTITY_PREFIX}${id}`
}

export function isObsIngressPublisherIdentity(identity: string): boolean {
  return identity.trim().startsWith(OBS_INGRESS_IDENTITY_PREFIX)
}
