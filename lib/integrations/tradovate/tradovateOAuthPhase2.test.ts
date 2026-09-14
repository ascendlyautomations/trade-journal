import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  encryptIntegrationCredentials,
  decryptIntegrationCredentials,
} from "@/lib/integrations/credentialEncryption"
import { parseTradovateIdTokenSubject } from "@/lib/integrations/tradovate/tradovateTokenExchange"
import {
  createTradovateAuthorizeHandoffValue,
  verifyTradovateAuthorizeHandoffValue,
} from "@/lib/integrations/tradovate/tradovateAuthorizeHandoff"

describe("tradovate OAuth phase 2", () => {
  it("round-trips encrypted integration credentials", () => {
    const prior = process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY
    process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString(
      "base64url"
    )
    try {
      const payload = {
        access_token: "access",
        refresh_token: "refresh",
        token_type: "Bearer",
      }
      const ciphertext = encryptIntegrationCredentials(payload)
      assert.match(ciphertext, /^v1:/)
      assert.deepEqual(decryptIntegrationCredentials(ciphertext), payload)
    } finally {
      if (prior === undefined) {
        delete process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY
      } else {
        process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = prior
      }
    }
  })

  it("signs and verifies authorize handoff cookie values", () => {
    const prior = process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY
    process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = Buffer.alloc(32, 9).toString(
      "base64url"
    )
    try {
      const value = createTradovateAuthorizeHandoffValue("user-abc")
      assert.equal(verifyTradovateAuthorizeHandoffValue(value), "user-abc")
      assert.equal(verifyTradovateAuthorizeHandoffValue(`${value}tampered`), null)
    } finally {
      if (prior === undefined) {
        delete process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY
      } else {
        process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = prior
      }
    }
  })

  it("parses id_token subject without verifying signature", () => {
    const header = Buffer.from(JSON.stringify({ alg: "none" })).toString("base64url")
    const payload = Buffer.from(JSON.stringify({ sub: "tradovate-user-99" })).toString(
      "base64url"
    )
    const idToken = `${header}.${payload}.sig`
    assert.equal(parseTradovateIdTokenSubject(idToken), "tradovate-user-99")
  })
})
