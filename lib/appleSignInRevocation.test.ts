import { describe, it, mock, afterEach, before } from "node:test"
import assert from "node:assert/strict"
import { generateKeyPairSync } from "node:crypto"
import {
  createAppleSignInClientSecret,
  exchangeAppleAuthorizationCode,
  revokeAppleRefreshToken,
  type AppleSignInOAuthConfig,
} from "./appleSignInOAuth.ts"
import { userHasAppleIdentity } from "./appleSignInCredentialStore.ts"
import {
  encryptIntegrationCredentials,
  decryptIntegrationCredentials,
} from "./integrations/credentialEncryption.ts"

let TEST_CONFIG: AppleSignInOAuthConfig

before(() => {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" })
  TEST_CONFIG = {
    teamId: "TEAM123",
    clientId: "com.tradetraxs.TradeTraxs",
    keyId: "KEY123",
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
  }
})

describe("appleSignInOAuth", () => {
  it("userHasAppleIdentity detects apple provider", () => {
    assert.equal(userHasAppleIdentity([{ provider: "google" }]), false)
    assert.equal(userHasAppleIdentity([{ provider: "apple" }]), true)
  })

  it("encrypts and decrypts apple refresh credential kind", () => {
    process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString(
      "base64url"
    )
    const ciphertext = encryptIntegrationCredentials({
      kind: "apple_sign_in_refresh",
      refresh_token: "rt-test",
    })
    const decrypted = decryptIntegrationCredentials(ciphertext)
    assert.equal(decrypted.kind, "apple_sign_in_refresh")
    if (decrypted.kind === "apple_sign_in_refresh") {
      assert.equal(decrypted.refresh_token, "rt-test")
    }
  })

  it("exchangeAppleAuthorizationCode stores refresh token from mocked Apple", async () => {
    const fetchImpl = mock.fn(async () =>
      Response.json({ refresh_token: "apple-refresh-1", id_token: "id" })
    )
    const result = await exchangeAppleAuthorizationCode(
      "auth-code-1",
      TEST_CONFIG,
      fetchImpl as unknown as typeof fetch
    )
    assert.equal(result.ok, true)
    if (result.ok) {
      assert.equal(result.refreshToken, "apple-refresh-1")
    }
  })

  it("revokeAppleRefreshToken succeeds on HTTP 200", async () => {
    const fetchImpl = mock.fn(async () => new Response("", { status: 200 }))
    const result = await revokeAppleRefreshToken(
      "apple-refresh-1",
      TEST_CONFIG,
      fetchImpl as unknown as typeof fetch
    )
    assert.equal(result.ok, true)
  })

  it("createAppleSignInClientSecret returns three JWT segments", () => {
    const secret = createAppleSignInClientSecret(TEST_CONFIG, 1_700_000_000)
    assert.equal(secret.split(".").length, 3)
  })
})

afterEach(() => {
  mock.reset()
})

export {}
