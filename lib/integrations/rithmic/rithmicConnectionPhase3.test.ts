import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  decryptIntegrationCredentials,
  encryptIntegrationCredentials,
  isRithmicIntegrationCredentials,
} from "@/lib/integrations/credentialEncryption"
import {
  assertRithmicConnectResponseSafe,
  sanitizeConnectRequestBody,
  sanitizeRithmicSyncRequestBody,
} from "@/lib/integrations/rithmic/rithmicConnectSafeResponse"

describe("Rithmic Phase 3 connection security", () => {
  const keyPrior = process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY

  it("credential encryption still supports legacy rithmic kind (passwords are not persisted)", () => {
    process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = Buffer.alloc(32, 3).toString(
      "base64url"
    )
    try {
      const ciphertext = encryptIntegrationCredentials({
        kind: "rithmic",
        username: "trader1",
        password: "secret-pass",
        systemName: "Rithmic Test",
        apiEnvironment: "test",
      })
      const decrypted = decryptIntegrationCredentials(ciphertext)
      assert.ok(isRithmicIntegrationCredentials(decrypted))
      assert.equal(decrypted.username, "trader1")
      assert.equal(decrypted.password, "secret-pass")
      assert.equal(decrypted.systemName, "Rithmic Test")
    } finally {
      if (keyPrior === undefined) delete process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY
      else process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = keyPrior
    }
  })

  it("sanitizeConnectRequestBody rejects missing password", () => {
    assert.equal(sanitizeConnectRequestBody({ username: "a" }), null)
  })

  it("sanitizeRithmicSyncRequestBody accepts password in POST body only", () => {
    assert.equal(sanitizeRithmicSyncRequestBody({}), null)
    assert.deepEqual(sanitizeRithmicSyncRequestBody({ password: "x" }), {
      password: "x",
    })
  })

  it("connect API response must not include password fields", () => {
    assert.throws(() =>
      assertRithmicConnectResponseSafe({
        ok: true,
        password: "leak",
      })
    )
    assert.doesNotThrow(() =>
      assertRithmicConnectResponseSafe({
        ok: true,
        connectionId: "uuid",
        systemName: "Rithmic Test",
        accountCount: 1,
      })
    )
  })
})
