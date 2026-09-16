import { createCipheriv, createDecipheriv, randomBytes } from "crypto"

const ALGORITHM = "aes-256-gcm"
const IV_BYTES = 12
const VERSION_PREFIX = "v1"

function encryptionKey(): Buffer {
  const raw = process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY?.trim()
  if (!raw) {
    throw new Error("integration_credentials_encryption_key_missing")
  }
  const key = Buffer.from(raw, "base64url")
  if (key.length !== 32) {
    throw new Error("integration_credentials_encryption_key_invalid")
  }
  return key
}

export type TradovateIntegrationCredentials = {
  kind: "tradovate"
  access_token: string
  refresh_token?: string | null
  token_type?: string | null
}

export type RithmicIntegrationCredentials = {
  kind: "rithmic"
  username: string
  password: string
  systemName: string
  apiEnvironment: "test"
}

export type AppleSignInRefreshCredentials = {
  kind: "apple_sign_in_refresh"
  refresh_token: string
}

export type IntegrationCredentialPayload =
  | TradovateIntegrationCredentials
  | RithmicIntegrationCredentials
  | AppleSignInRefreshCredentials

/** @deprecated Prefer IntegrationCredentialPayload with `kind`. */
export type LegacyTradovateCredentialPayload = {
  access_token: string
  refresh_token?: string | null
  token_type?: string | null
}

function normalizeEncryptPayload(
  payload: IntegrationCredentialPayload | LegacyTradovateCredentialPayload
): IntegrationCredentialPayload {
  if ("kind" in payload && payload.kind === "rithmic") {
    if (!payload.username?.trim() || !payload.password) {
      throw new Error("integration_credentials_payload_invalid")
    }
    if (!payload.systemName?.trim()) {
      throw new Error("integration_credentials_payload_invalid")
    }
    return payload
  }
  if ("kind" in payload && payload.kind === "tradovate") {
    if (!payload.access_token || typeof payload.access_token !== "string") {
      throw new Error("integration_credentials_payload_invalid")
    }
    return payload
  }
  if ("kind" in payload && payload.kind === "apple_sign_in_refresh") {
    if (!payload.refresh_token || typeof payload.refresh_token !== "string") {
      throw new Error("integration_credentials_payload_invalid")
    }
    return payload
  }
  const legacy = payload as LegacyTradovateCredentialPayload
  if (!legacy.access_token || typeof legacy.access_token !== "string") {
    throw new Error("integration_credentials_payload_invalid")
  }
  return {
    kind: "tradovate",
    access_token: legacy.access_token,
    refresh_token: legacy.refresh_token ?? null,
    token_type: legacy.token_type ?? null,
  }
}

function parseDecryptedPayload(parsed: unknown): IntegrationCredentialPayload {
  if (!parsed || typeof parsed !== "object") {
    throw new Error("integration_credentials_payload_invalid")
  }
  const o = parsed as Record<string, unknown>
  if (o.kind === "rithmic") {
    if (
      typeof o.username !== "string" ||
      typeof o.password !== "string" ||
      typeof o.systemName !== "string"
    ) {
      throw new Error("integration_credentials_payload_invalid")
    }
    return {
      kind: "rithmic",
      username: o.username,
      password: o.password,
      systemName: o.systemName,
      apiEnvironment: o.apiEnvironment === "test" ? "test" : "test",
    }
  }
  if (o.kind === "apple_sign_in_refresh") {
    if (typeof o.refresh_token !== "string" || !o.refresh_token.trim()) {
      throw new Error("integration_credentials_payload_invalid")
    }
    return {
      kind: "apple_sign_in_refresh",
      refresh_token: o.refresh_token,
    }
  }
  if (o.kind === "tradovate") {
    if (typeof o.access_token !== "string" || !o.access_token) {
      throw new Error("integration_credentials_payload_invalid")
    }
    return {
      kind: "tradovate",
      access_token: o.access_token,
      refresh_token: typeof o.refresh_token === "string" ? o.refresh_token : null,
      token_type: typeof o.token_type === "string" ? o.token_type : null,
    }
  }
  if (typeof o.access_token === "string" && o.access_token) {
    return {
      kind: "tradovate",
      access_token: o.access_token,
      refresh_token: typeof o.refresh_token === "string" ? o.refresh_token : null,
      token_type: typeof o.token_type === "string" ? o.token_type : null,
    }
  }
  throw new Error("integration_credentials_payload_invalid")
}

export function encryptIntegrationCredentials(
  payload: IntegrationCredentialPayload | LegacyTradovateCredentialPayload
): string {
  const key = encryptionKey()
  const iv = randomBytes(IV_BYTES)
  const cipher = createCipheriv(ALGORITHM, key, iv)
  const normalized = normalizeEncryptPayload(payload)
  const plaintext = JSON.stringify(normalized)
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()])
  const tag = cipher.getAuthTag()
  return [
    VERSION_PREFIX,
    iv.toString("base64url"),
    encrypted.toString("base64url"),
    tag.toString("base64url"),
  ].join(":")
}

export function decryptIntegrationCredentials(
  ciphertext: string
): IntegrationCredentialPayload {
  const key = encryptionKey()
  const parts = ciphertext.split(":")
  if (parts.length !== 4 || parts[0] !== VERSION_PREFIX) {
    throw new Error("integration_credentials_ciphertext_invalid")
  }
  const iv = Buffer.from(parts[1]!, "base64url")
  const encrypted = Buffer.from(parts[2]!, "base64url")
  const tag = Buffer.from(parts[3]!, "base64url")
  const decipher = createDecipheriv(ALGORITHM, key, iv)
  decipher.setAuthTag(tag)
  const plaintext = Buffer.concat([decipher.update(encrypted), decipher.final()]).toString(
    "utf8"
  )
  const parsed = JSON.parse(plaintext) as unknown
  return parseDecryptedPayload(parsed)
}

export function isTradovateIntegrationCredentials(
  payload: IntegrationCredentialPayload
): payload is TradovateIntegrationCredentials {
  return payload.kind === "tradovate"
}

export function isRithmicIntegrationCredentials(
  payload: IntegrationCredentialPayload
): payload is RithmicIntegrationCredentials {
  return payload.kind === "rithmic"
}
