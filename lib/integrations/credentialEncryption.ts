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

export type IntegrationCredentialPayload = {
  access_token: string
  refresh_token?: string | null
  token_type?: string | null
}

export function encryptIntegrationCredentials(
  payload: IntegrationCredentialPayload
): string {
  const key = encryptionKey()
  const iv = randomBytes(IV_BYTES)
  const cipher = createCipheriv(ALGORITHM, key, iv)
  const plaintext = JSON.stringify(payload)
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
  const parsed = JSON.parse(plaintext) as IntegrationCredentialPayload
  if (!parsed.access_token || typeof parsed.access_token !== "string") {
    throw new Error("integration_credentials_payload_invalid")
  }
  return parsed
}
