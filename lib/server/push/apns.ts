import crypto from "crypto"
import http2 from "http2"
import { NATIVE_IOS_APP_ID } from "@/lib/nativeIosIdentity"

export type ApnsAlertPayload = {
  title: string
  body: string
  href: string
  badge: number
  notificationType: string
  /** iOS notification category for long-press actions. */
  category?: string
  conversationId?: string
  roomId?: string
  roomSlug?: string
  followRequestId?: string
  /** Actor profile UUID — native follow / social deep links resolve by id. */
  senderId?: string
  /**
   * APNs thread-id — groups related alerts in Notification Center.
   * For DMs this is stable per conversation (`dm:{conversationId}`).
   */
  threadId?: string
  /**
   * APNs collapse-id — replaces a prior undelivered/delivered alert with the
   * same id so rapid messages in one conversation become one evolving banner.
   */
  collapseId?: string
}

/** Keep alerts eligible for offline delivery (~24h). `0` means expire immediately. */
const APNS_EXPIRATION_TTL_SECONDS = 24 * 60 * 60

type ApnsConfig = {
  keyId: string
  teamId: string
  bundleId: string
  privateKeyPem: string
  production: boolean
}

function readApnsConfig(): ApnsConfig | null {
  const keyId = process.env.APNS_KEY_ID?.trim()
  const teamId = process.env.APNS_TEAM_ID?.trim()
  const bundleId =
    process.env.APNS_BUNDLE_ID?.trim() || NATIVE_IOS_APP_ID
  const rawKey = process.env.APNS_PRIVATE_KEY?.trim()
  if (!keyId || !teamId || !rawKey) return null

  let privateKeyPem = rawKey
  if (!rawKey.includes("BEGIN")) {
    try {
      privateKeyPem = Buffer.from(rawKey, "base64").toString("utf8")
    } catch {
      return null
    }
  }
  privateKeyPem = privateKeyPem.replace(/\\n/g, "\n")

  return {
    keyId,
    teamId,
    bundleId,
    privateKeyPem,
    production: process.env.APNS_PRODUCTION === "true",
  }
}

let cachedJwt: { token: string; expiresAt: number } | null = null

function createApnsJwt(config: ApnsConfig): string {
  const now = Math.floor(Date.now() / 1000)
  if (cachedJwt && cachedJwt.expiresAt > now + 60) {
    return cachedJwt.token
  }

  const header = Buffer.from(
    JSON.stringify({ alg: "ES256", kid: config.keyId })
  ).toString("base64url")
  const claims = Buffer.from(
    JSON.stringify({ iss: config.teamId, iat: now })
  ).toString("base64url")
  const signingInput = `${header}.${claims}`
  const signer = crypto.createSign("SHA256")
  signer.update(signingInput)
  signer.end()
  const signature = signer
    .sign({ key: config.privateKeyPem, dsaEncoding: "ieee-p1363" })
    .toString("base64url")
  const token = `${signingInput}.${signature}`
  // APNs JWTs are valid up to 1 hour.
  cachedJwt = { token, expiresAt: now + 50 * 60 }
  return token
}

export type ApnsSendResult =
  | { ok: true }
  | { ok: false; status: number; reason: string; invalidToken: boolean }

/**
 * APNs reasons where this device token can never succeed for our current
 * topic / environment. Safe to delete from `device_push_tokens`.
 *
 * Do NOT include transient or request/config errors (TooManyRequests,
 * InternalServerError, PayloadTooLarge, BadTopic, Forbidden, etc.).
 */
export function isPermanentlyInvalidApnsToken(
  status: number,
  reason: string
): boolean {
  const normalized = reason.trim()
  if (status === 410) return true
  switch (normalized) {
    case "BadDeviceToken":
    // Malformed token, or token for the opposite APNs environment.
    case "Unregistered":
    // Token inactive for this topic (uninstall / invalidated).
    case "ExpiredToken":
    // Token expired for this topic (410 companion reason).
    case "DeviceTokenNotForTopic":
      // Token was issued for a different App ID / bundle topic (old build,
      // renamed bundle, simulator/wrong target). Will never work with our
      // current apns-topic.
      return true
    default:
      return false
  }
}

export function isApnsConfigured(): boolean {
  return readApnsConfig() != null
}

/** Safe for status endpoints — never exposes key material. */
export function getApnsRuntimeInfo(): {
  configured: boolean
  production: boolean
  bundleId: string
} {
  const config = readApnsConfig()
  if (!config) {
    return {
      configured: false,
      production: false,
      bundleId: NATIVE_IOS_APP_ID,
    }
  }
  return {
    configured: true,
    production: config.production,
    bundleId: config.bundleId,
  }
}

const APNS_REQUEST_TIMEOUT_MS = 12_000

export async function sendApnsAlert(
  deviceToken: string,
  payload: ApnsAlertPayload
): Promise<ApnsSendResult> {
  const config = readApnsConfig()
  if (!config) {
    return { ok: false, status: 0, reason: "apns_not_configured", invalidToken: false }
  }

  const host = config.production
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com"

  // Custom keys outside `aps` are consumed by the native Swift push parser
  // (tap routing via `href` / `type` and notification actions).
  const body = JSON.stringify({
    aps: {
      alert: {
        title: payload.title,
        body: payload.body,
      },
      badge: Math.max(0, Math.floor(payload.badge)),
      sound: "default",
      ...(payload.category ? { category: payload.category } : {}),
      ...(payload.threadId ? { "thread-id": payload.threadId } : {}),
    },
    href: payload.href,
    type: payload.notificationType,
    ...(payload.conversationId
      ? { conversationId: payload.conversationId }
      : {}),
    ...(payload.roomId ? { roomId: payload.roomId } : {}),
    ...(payload.roomSlug ? { roomSlug: payload.roomSlug } : {}),
    ...(payload.followRequestId
      ? { followRequestId: payload.followRequestId }
      : {}),
    ...(payload.senderId ? { senderId: payload.senderId } : {}),
  })

  const jwt = createApnsJwt(config)

  // TEMPORARY [tt-push-debug] — exact payload after APNs accept path starts.
  console.info("[tt-push-debug] APNs request", {
    timestamp: new Date().toISOString(),
    host: config.production
      ? "api.push.apple.com"
      : "api.sandbox.push.apple.com",
    environment: config.production ? "production" : "sandbox",
    bundleId: config.bundleId,
    deviceToken,
    notificationType: payload.notificationType,
    apsPayload: JSON.parse(body) as unknown,
  })

  return await new Promise<ApnsSendResult>((resolve) => {
    let settled = false
    let client: http2.ClientHttp2Session | null = null
    let timer: ReturnType<typeof setTimeout> | null = null

    const finish = (result: ApnsSendResult) => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      try {
        client?.close()
      } catch {
        /* ignore */
      }
      resolve(result)
    }

    timer = setTimeout(() => {
      try {
        client?.destroy()
      } catch {
        /* ignore */
      }
      finish({
        ok: false,
        status: 0,
        reason: "timeout",
        invalidToken: false,
      })
    }, APNS_REQUEST_TIMEOUT_MS)

    try {
      client = http2.connect(host)
    } catch (err) {
      finish({
        ok: false,
        status: 0,
        reason: err instanceof Error ? err.message : "connect_failed",
        invalidToken: false,
      })
      return
    }

    client.on("error", (err) => {
      finish({
        ok: false,
        status: 0,
        reason: err.message,
        invalidToken: false,
      })
    })

    const collapseId = payload.collapseId?.trim().slice(0, 64)
    const expiration = String(
      Math.floor(Date.now() / 1000) + APNS_EXPIRATION_TTL_SECONDS
    )
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": expiration,
      "content-type": "application/json",
      ...(collapseId ? { "apns-collapse-id": collapseId } : {}),
    })

    let status = 0
    const chunks: Buffer[] = []

    req.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0)
    })
    req.on("data", (chunk) => {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk))
    })
    req.on("end", () => {
      const responseBody = Buffer.concat(chunks).toString("utf8")
      if (status === 200) {
        // TEMPORARY [tt-push-debug]
        console.info("[tt-push-debug] APNs accepted (200)", {
          timestamp: new Date().toISOString(),
          deviceToken,
          notificationType: payload.notificationType,
          title: payload.title,
          body: payload.body,
          environment: config.production ? "production" : "sandbox",
          bundleId: config.bundleId,
        })
        finish({ ok: true })
        return
      }
      let reason = "unknown"
      try {
        const parsed = JSON.parse(responseBody) as {
          reason?: string
        }
        reason = parsed.reason ?? reason
      } catch {
        /* ignore */
      }
      // TEMPORARY [tt-push-debug]
      console.error("[tt-push-debug] APNs rejected", {
        timestamp: new Date().toISOString(),
        deviceToken,
        notificationType: payload.notificationType,
        status,
        reason,
        responseBody: responseBody.slice(0, 500),
        environment: config.production ? "production" : "sandbox",
        bundleId: config.bundleId,
      })
      const invalidToken = isPermanentlyInvalidApnsToken(status, reason)
      finish({ ok: false, status, reason, invalidToken })
    })
    req.on("error", (err) => {
      finish({
        ok: false,
        status: 0,
        reason: err.message,
        invalidToken: false,
      })
    })

    req.end(body)
  })
}
