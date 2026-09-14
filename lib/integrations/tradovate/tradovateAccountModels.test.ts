import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { normalizeTradovateAccountRow } from "./tradovateAccountModels"

describe("tradovateAccountModels", () => {
  it("normalizes official Account list fields", () => {
    const normalized = normalizeTradovateAccountRow({
      id: 10234,
      name: "Primary Trading Account",
      userId: 5678,
      accountType: "Customer",
      closed: false,
      evaluationSize: 250000.75,
    })
    assert.ok(normalized)
    assert.equal(normalized.externalAccountId, "10234")
    assert.equal(normalized.name, "Primary Trading Account")
    assert.equal(normalized.active, true)
    assert.equal(normalized.evaluationSize, 250000.75)
    assert.equal(normalized.providerUserId, "5678")
  })

  it("drops rows without stable provider account id", () => {
    assert.equal(normalizeTradovateAccountRow({ name: "x" }), null)
  })
})
