import { createPrivateKey, sign } from "node:crypto"
import { APPLE_TEAM_ID } from "./appleAppSiteAssociation.ts"
import { NATIVE_IOS_APP_ID } from "./nativeIosIdentity.ts"

const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke"
const APPLE_AUDIENCE = "https://appleid.apple.com"
const CLIENT_SECRET_MAX_AGE_SECONDS = 15777000 // ~182 days (Apple allows up to 6 months)

export type AppleSignInOAuthConfig = {
  teamId: string
  clientId: string
  keyId: string
  privateKeyPem: string
}

export type AppleTokenExchangeResult =
  | { ok: true; refreshToken: string; idToken?: string }
  | { ok: false; reason: "misconfigured" | "apple_rejected" | "network" }

export type AppleRevokeFailureReason =
  | "misconfigured"
  | "retryable"
  | "terminal"

export type AppleTokenRevokeResult =
  | { ok: true }
  | { ok: false; reason: AppleRevokeFailureReason; httpStatus?: number }

/** Classify Apple /auth/revoke HTTP responses (no token material in errors). */
export function classifyAppleRevokeHttpResponse(
  status: number,
  errorCode: string | null
): AppleRevokeFailureReason {
  const code = (errorCode ?? "").toLowerCase()
  if (status >= 500 || status === 429) {
    return "retryable"
  }
  // Apple documents 200 on success; invalid/expired/already-revoked tokens are not usefully retried.
  if (
    code === "invalid_grant" ||
    code === "invalid_token" ||
    code === "unsupported_grant_type"
  ) {
    return "terminal"
  }
  if (status === 400 || status === 401 || status === 403) {
    return code === "invalid_client" ? "misconfigured" : "terminal"
  }
  return "retryable"
}

async function readAppleRevokeErrorCode(response: Response): Promise<string | null> {
  try {
    const text = await response.text()
    if (!text.trim()) return null
    const params = new URLSearchParams(text)
    const fromForm = params.get("error")
    if (fromForm) return fromForm
    const json = JSON.parse(text) as { error?: string }
    return typeof json.error === "string" ? json.error : null
  } catch {
    return null
  }
}

function readAppleSignInPrivateKeyPem(): string {
  const raw = process.env.APPLE_SIGN_IN_PRIVATE_KEY?.trim() ?? ""
  if (!raw) return ""
  if (raw.includes("BEGIN PRIVATE KEY")) {
    return raw.replace(/\\n/g, "\n")
  }
  return Buffer.from(raw, "base64").toString("utf8")
}

export function appleSignInOAuthConfigured(): boolean {
  return Boolean(
    resolveAppleTeamId() &&
      process.env.APPLE_SIGN_IN_KEY_ID?.trim() &&
      readAppleSignInPrivateKeyPem() &&
      (process.env.APPLE_SIGN_IN_CLIENT_ID?.trim() || NATIVE_IOS_APP_ID)
  )
}

function resolveAppleTeamId(): string {
  return process.env.APPLE_TEAM_ID?.trim() || APPLE_TEAM_ID
}

export function resolveAppleSignInOAuthConfig(): AppleSignInOAuthConfig | null {
  const teamId = resolveAppleTeamId()
  const keyId = process.env.APPLE_SIGN_IN_KEY_ID?.trim()
  const privateKeyPem = readAppleSignInPrivateKeyPem()
  const clientId =
    process.env.APPLE_SIGN_IN_CLIENT_ID?.trim() || NATIVE_IOS_APP_ID
  if (!teamId || !keyId || !privateKeyPem || !clientId) return null
  return { teamId, clientId, keyId, privateKeyPem }
}

function base64UrlJson(value: Record<string, unknown> | { alg: string; kid: string }): string {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url")
}

export function createAppleSignInClientSecret(
  config: AppleSignInOAuthConfig,
  nowSeconds = Math.floor(Date.now() / 1000)
): string {
  const header = { alg: "ES256", kid: config.keyId }
  const payload = {
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + CLIENT_SECRET_MAX_AGE_SECONDS,
    aud: APPLE_AUDIENCE,
    sub: config.clientId,
  }
  const signingInput = `${base64UrlJson(header)}.${base64UrlJson(payload)}`
  const key = createPrivateKey(config.privateKeyPem)
  const signature = sign("sha256", Buffer.from(signingInput, "utf8"), {
    key,
    dsaEncoding: "ieee-p1363",
  })
  return `${signingInput}.${signature.toString("base64url")}`
}

type AppleFetch = typeof fetch

function formBody(params: Record<string, string>): string {
  return new URLSearchParams(params).toString()
}

export async function exchangeAppleAuthorizationCode(
  authorizationCode: string,
  config: AppleSignInOAuthConfig,
  fetchImpl: AppleFetch = fetch
): Promise<AppleTokenExchangeResult> {
  const code = authorizationCode.trim()
  if (!code) {
    return { ok: false, reason: "apple_rejected" }
  }
  let clientSecret: string
  try {
    clientSecret = createAppleSignInClientSecret(config)
  } catch {
    return { ok: false, reason: "misconfigured" }
  }

  try {
    const response = await fetchImpl(APPLE_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: formBody({
        client_id: config.clientId,
        client_secret: clientSecret,
        code,
        grant_type: "authorization_code",
      }),
    })
    if (!response.ok) {
      return { ok: false, reason: "apple_rejected" }
    }
    const json = (await response.json()) as {
      refresh_token?: string
      id_token?: string
    }
    const refreshToken = json.refresh_token?.trim()
    if (!refreshToken) {
      return { ok: false, reason: "apple_rejected" }
    }
    return {
      ok: true,
      refreshToken,
      idToken: json.id_token?.trim() || undefined,
    }
  } catch {
    return { ok: false, reason: "network" }
  }
}

export async function revokeAppleRefreshToken(
  refreshToken: string,
  config: AppleSignInOAuthConfig,
  fetchImpl: AppleFetch = fetch
): Promise<AppleTokenRevokeResult> {
  const token = refreshToken.trim()
  if (!token) {
    return { ok: false, reason: "terminal" }
  }
  let clientSecret: string
  try {
    clientSecret = createAppleSignInClientSecret(config)
  } catch {
    return { ok: false, reason: "misconfigured" }
  }

  try {
    const response = await fetchImpl(APPLE_REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: formBody({
        client_id: config.clientId,
        client_secret: clientSecret,
        token,
        token_type_hint: "refresh_token",
      }),
    })
    if (response.ok) {
      return { ok: true }
    }
    const errorCode = await readAppleRevokeErrorCode(response)
    return {
      ok: false,
      reason: classifyAppleRevokeHttpResponse(response.status, errorCode),
      httpStatus: response.status,
    }
  } catch {
    return { ok: false, reason: "retryable" }
  }
}
