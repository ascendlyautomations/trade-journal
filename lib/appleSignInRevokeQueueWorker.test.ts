import { describe, it, mock, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { generateKeyPairSync } from "node:crypto"
import {
  computeAppleRevokeQueueNextAttemptAt,
  processAppleSignInRevokeQueue,
  APPLE_REVOKE_QUEUE_BACKOFF_BASE_MS,
  APPLE_REVOKE_QUEUE_MAX_ATTEMPTS,
} from "./appleSignInRevokeQueueWorker.ts"
import { classifyAppleRevokeHttpResponse } from "./appleSignInOAuth.ts"
import {
  encryptIntegrationCredentials,
  decryptIntegrationCredentials,
} from "./integrations/credentialEncryption.ts"

describe("appleSignInRevokeQueueWorker", () => {
  const envBackup = { ...process.env }

  beforeEach(() => {
    process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = Buffer.alloc(32, 9).toString(
      "base64url"
    )
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" })
    process.env.APPLE_SIGN_IN_KEY_ID = "KEY1"
    process.env.APPLE_SIGN_IN_PRIVATE_KEY = privateKey
      .export({ type: "pkcs8", format: "pem" })
      .toString()
    process.env.APPLE_SIGN_IN_CLIENT_ID = "com.tradetraxs.TradeTraxs"
  })

  afterEach(() => {
    process.env = { ...envBackup }
    mock.reset()
  })

  it("classifies invalid_grant as terminal", () => {
    assert.equal(classifyAppleRevokeHttpResponse(400, "invalid_grant"), "terminal")
  })

  it("classifies 503 as retryable", () => {
    assert.equal(classifyAppleRevokeHttpResponse(503, null), "retryable")
  })

  it("backoff grows but is capped", () => {
    const first = computeAppleRevokeQueueNextAttemptAt(1, 0)
    const late = computeAppleRevokeQueueNextAttemptAt(10, 0)
    assert.equal(first, new Date(APPLE_REVOKE_QUEUE_BACKOFF_BASE_MS).toISOString())
    assert.ok(new Date(late).getTime() <= 24 * 60 * 60 * 1000)
  })

  it("worker deletes queue row when Apple revoke succeeds", async () => {
    const ciphertext = encryptIntegrationCredentials({
      kind: "apple_sign_in_refresh",
      refresh_token: "rt-worker-1",
    })
    const deleted: string[] = []
    const fetchImpl = mock.fn(async () => new Response("", { status: 200 }))

    const supabase = {
      rpc: async () => ({
        data: [
          {
            id: "q1",
            client_id: "com.tradetraxs.TradeTraxs",
            refresh_token_ciphertext: ciphertext,
            attempts: 0,
            last_error: null,
            created_at: new Date().toISOString(),
            next_attempt_at: new Date().toISOString(),
            lease_expires_at: null,
          },
        ],
        error: null,
      }),
      from: (table: string) => ({
        delete: () => ({
          eq: async (_col: string, id: string) => {
            if (table === "apple_sign_in_revoke_queue") deleted.push(id)
            return { error: null }
          },
        }),
        update: () => ({
          eq: async () => ({ error: null }),
        }),
      }),
    }

    const result = await processAppleSignInRevokeQueue(supabase as never, {
      fetchImpl: fetchImpl as unknown as typeof fetch,
    })
    assert.equal(result.revoked, 1)
    assert.deepEqual(deleted, ["q1"])
    assert.equal(fetchImpl.mock.calls.length, 1)
  })

  it("worker reschedules on retryable failure", async () => {
    const ciphertext = encryptIntegrationCredentials({
      kind: "apple_sign_in_refresh",
      refresh_token: "rt-worker-2",
    })
    let updatedAttempts: number | null = null
    const fetchImpl = mock.fn(async () => new Response("", { status: 503 }))

    const supabase = {
      rpc: async () => ({
        data: [
          {
            id: "q2",
            client_id: "com.tradetraxs.TradeTraxs",
            refresh_token_ciphertext: ciphertext,
            attempts: 1,
            last_error: "retryable",
            created_at: new Date().toISOString(),
            next_attempt_at: new Date().toISOString(),
            lease_expires_at: null,
          },
        ],
        error: null,
      }),
      from: () => ({
        delete: () => ({
          eq: async () => ({ error: null }),
        }),
        update: (payload: { attempts: number }) => ({
          eq: async () => {
            updatedAttempts = payload.attempts
            return { error: null }
          },
        }),
      }),
    }

    const result = await processAppleSignInRevokeQueue(supabase as never, {
      fetchImpl: fetchImpl as unknown as typeof fetch,
    })
    assert.equal(result.rescheduled, 1)
    assert.equal(updatedAttempts, 2)
  })

  it("worker removes row on terminal Apple response", async () => {
    const ciphertext = encryptIntegrationCredentials({
      kind: "apple_sign_in_refresh",
      refresh_token: "rt-worker-3",
    })
    const deleted: string[] = []
    const fetchImpl = mock.fn(async () =>
      new Response("error=invalid_grant", {
        status: 400,
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
      })
    )

    const supabase = {
      rpc: async () => ({
        data: [
          {
            id: "q3",
            client_id: "com.tradetraxs.TradeTraxs",
            refresh_token_ciphertext: ciphertext,
            attempts: 0,
            last_error: null,
            created_at: new Date().toISOString(),
            next_attempt_at: new Date().toISOString(),
            lease_expires_at: null,
          },
        ],
        error: null,
      }),
      from: () => ({
        delete: () => ({
          eq: async (_c: string, id: string) => {
            deleted.push(id)
            return { error: null }
          },
        }),
        update: () => ({
          eq: async () => ({ error: null }),
        }),
      }),
    }

    const result = await processAppleSignInRevokeQueue(supabase as never, {
      fetchImpl: fetchImpl as unknown as typeof fetch,
    })
    assert.equal(result.removedTerminal, 1)
    assert.deepEqual(deleted, ["q3"])
  })

  it("drops queue row after max attempts", async () => {
    const ciphertext = encryptIntegrationCredentials({
      kind: "apple_sign_in_refresh",
      refresh_token: "rt-worker-4",
    })
    const deleted: string[] = []
    const fetchImpl = mock.fn(async () => new Response("", { status: 503 }))

    const supabase = {
      rpc: async () => ({
        data: [
          {
            id: "q4",
            client_id: "com.tradetraxs.TradeTraxs",
            refresh_token_ciphertext: ciphertext,
            attempts: APPLE_REVOKE_QUEUE_MAX_ATTEMPTS,
            last_error: "retryable",
            created_at: new Date().toISOString(),
            next_attempt_at: new Date().toISOString(),
            lease_expires_at: null,
          },
        ],
        error: null,
      }),
      from: () => ({
        delete: () => ({
          eq: async (_c: string, id: string) => {
            deleted.push(id)
            return { error: null }
          },
        }),
        update: () => ({
          eq: async () => ({ error: null }),
        }),
      }),
    }

    const result = await processAppleSignInRevokeQueue(supabase as never, {
      fetchImpl: fetchImpl as unknown as typeof fetch,
    })
    assert.equal(result.removedExpired, 1)
    assert.deepEqual(deleted, ["q4"])
    assert.equal(fetchImpl.mock.calls.length, 0)
  })
})

export {}
