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

  // Custom keys outside `aps` are mapped into Capacitor `notification.data`
  // (used for tap routing via `data.href` and notification actions).
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
  })

  const jwt = createApnsJwt(config)

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
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": "0",
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
      if (status === 200) {
        finish({ ok: true })
        return
      }
      let reason = "unknown"
      try {
        const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8")) as {
          reason?: string
        }
        reason = parsed.reason ?? reason
      } catch {
        /* ignore */
      }
      const invalidToken =
        status === 410 ||
        reason === "BadDeviceToken" ||
        reason === "Unregistered" ||
        reason === "ExpiredToken"
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
