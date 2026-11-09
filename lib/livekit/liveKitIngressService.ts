import { IngressClient } from "livekit-server-sdk"
import {
  IngressInput,
  IngressState_Status,
  type IngressInfo,
} from "@livekit/protocol"
import { readLiveKitServerConfig, type LiveKitServerConfig } from "./config.ts"
import { liveKitBroadcastRoomName } from "./liveKitRoomName.ts"

let cachedIngressClient: IngressClient | null = null

export function getLiveKitIngressClient(): IngressClient | null {
  const config = readLiveKitServerConfig()
  if (!config) return null
  if (!cachedIngressClient) {
    cachedIngressClient = new IngressClient(
      config.livekitUrl,
      config.apiKey,
      config.apiSecret
    )
  }
  return cachedIngressClient
}

/**
 * Verify LiveKit Ingress API is callable (cloud project with Ingress, or self-hosted with ingress enabled).
 */
export async function probeLiveKitIngressAvailable(): Promise<
  { ok: true } | { ok: false; error: string }
> {
  const client = getLiveKitIngressClient()
  if (!client) {
    return { ok: false, error: "LiveKit is not configured on the server." }
  }
  try {
    await client.listIngress({ roomName: "__tradetraxs_ingress_probe__" })
    return { ok: true }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    if (/404|not supported|unavailable|unknown method|ingress/i.test(message)) {
      return {
        ok: false,
        error:
          "LiveKit Ingress is not available for this project. Enable Ingress on LiveKit Cloud or configure a self-hosted server with Ingress.",
      }
    }
    return { ok: true }
  }
}

export type CreateObsRtmpIngressParams = {
  roomId: string
  participantIdentity: string
  participantDisplayName: string
}

export async function createObsRtmpIngress(
  params: CreateObsRtmpIngressParams
): Promise<{ ok: true; info: IngressInfo } | { ok: false; error: string }> {
  const probe = await probeLiveKitIngressAvailable()
  if (!probe.ok) {
    return { ok: false, error: probe.error }
  }
  const client = getLiveKitIngressClient()
  if (!client) {
    return { ok: false, error: "LiveKit is not configured on the server." }
  }

  const roomName = liveKitBroadcastRoomName(params.roomId)
  try {
    const info = await client.createIngress(IngressInput.RTMP_INPUT, {
      name: `tt-broadcast-${params.roomId.slice(0, 8)}`,
      roomName,
      participantIdentity: params.participantIdentity,
      participantName: params.participantDisplayName,
      participantMetadata: JSON.stringify({
        kind: "tradetraxs_broadcast_obs",
        roomId: params.roomId,
      }),
    })
    return { ok: true, info }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return { ok: false, error: message }
  }
}

export async function deleteLiveKitIngress(
  ingressId: string
): Promise<{ ok: true } | { ok: false; error: string }> {
  const client = getLiveKitIngressClient()
  if (!client) {
    return { ok: false, error: "LiveKit is not configured on the server." }
  }
  const id = ingressId.trim()
  if (!id) {
    return { ok: true }
  }
  try {
    await client.deleteIngress(id)
    return { ok: true }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    if (/not found|does not exist|404/i.test(message)) {
      return { ok: true }
    }
    return { ok: false, error: message }
  }
}

export async function getIngressInfo(
  ingressId: string
): Promise<
  { ok: true; info: IngressInfo | null } | { ok: false; error: string }
> {
  const client = getLiveKitIngressClient()
  if (!client) {
    return { ok: false, error: "LiveKit is not configured on the server." }
  }
  const id = ingressId.trim()
  if (!id) {
    return { ok: true, info: null }
  }
  try {
    const items = await client.listIngress({ ingressId: id })
    return { ok: true, info: items[0] ?? null }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return { ok: false, error: message }
  }
}

/** Maps LiveKit enum to a small string for DB / API (no secrets). */
export function ingressStatusLabel(info: IngressInfo | null | undefined): string | null {
  if (!info?.state) return null
  switch (info.state.status) {
    case IngressState_Status.ENDPOINT_INACTIVE:
      return "ENDPOINT_INACTIVE"
    case IngressState_Status.ENDPOINT_BUFFERING:
      return "ENDPOINT_BUFFERING"
    case IngressState_Status.ENDPOINT_PUBLISHING:
      return "ENDPOINT_PUBLISHING"
    case IngressState_Status.ENDPOINT_ERROR:
      return "ENDPOINT_ERROR"
    case IngressState_Status.ENDPOINT_COMPLETE:
      return "ENDPOINT_COMPLETE"
    default:
      return "unknown"
  }
}

/** True when the ingress endpoint is allocated but no encoder is pushing yet. */
export function isIngressWaitingForEncoder(
  info: IngressInfo | null | undefined
): boolean {
  return info?.state?.status === IngressState_Status.ENDPOINT_INACTIVE
}

export function readLiveKitWsHost(config: LiveKitServerConfig): string {
  const raw = config.livekitUrl.trim()
  try {
    const u = new URL(raw)
    return u.host
  } catch {
    return raw.replace(/^wss?:\/\//i, "").replace(/\/$/, "")
  }
}
