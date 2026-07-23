import crypto from "crypto"
import http2 from "http2"

export type ApnsAlertPayload = {
  title: string
  body: string
  href: string
  badge: number
  notificationType: string
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
    process.env.APNS_BUNDLE_ID?.trim() || "com.tradetraxs.app"
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

  const body = JSON.stringify({
    aps: {
      alert: {
        title: payload.title,
        body: payload.body,
      },
      badge: Math.max(0, Math.floor(payload.badge)),
      sound: "default",
    },
    href: payload.href,
    type: payload.notificationType,
  })

  const jwt = createApnsJwt(config)

  return await new Promise<ApnsSendResult>((resolve) => {
    let settled = false
    const finish = (result: ApnsSendResult) => {
      if (settled) return
      settled = true
      resolve(result)
    }

    let client: http2.ClientHttp2Session
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

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": config.bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
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
      client.close()
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
      client.close()
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
