export type ObsIngressTelemetryEvent =
  | "claim_lease"
  | "claim_lease_in_progress"
  | "claim_lease_already_attached"
  | "create_ingress"
  | "create_ingress_failed"
  | "attach_ingress"
  | "attach_ingress_failed"
  | "delete_ingress"
  | "delete_ingress_failed"
  | "release_lease"
  | "cancel_preparation"
  | "orphan_ingress_deleted"
  | "stale_session_ended"

export function logObsIngressLifecycle(
  event: ObsIngressTelemetryEvent,
  details: {
    roomId: string
    sessionId: string
    ingressId?: string | null
    leaseToken?: string | null
    error?: string | null
    extra?: Record<string, unknown>
  }
): void {
  const payload = {
    event,
    roomId: details.roomId,
    sessionId: details.sessionId,
    ingressId: details.ingressId?.trim() || null,
    leaseToken: details.leaseToken?.trim() || null,
    error: details.error?.trim() || null,
    ...details.extra,
  }
  console.info("[livekit/obs-ingress]", JSON.stringify(payload))
}