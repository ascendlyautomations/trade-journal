import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  mergeRithmicFillCheckpoint,
  normalizeRithmicSymbolRoot,
  parseRithmicExternalAccountParts,
  readRithmicFillCheckpoint,
  rithmicExecutedAtFromSsboe,
  rithmicSideFromTransactionType,
  stableRithmicFillId,
} from "./rithmicFillModels.ts"

describe("Rithmic fill models", () => {
  it("parses external account tripartite id", () => {
    const p = parseRithmicExternalAccountParts("FCM|IB|ACC123")
    assert.deepEqual(p, { fcmId: "FCM", ibId: "IB", accountId: "ACC123" })
    assert.equal(parseRithmicExternalAccountParts("bad"), null)
  })

  it("maps official transaction_type BUY/SELL", () => {
    assert.equal(rithmicSideFromTransactionType(1), "Buy")
    assert.equal(rithmicSideFromTransactionType(2), "Sell")
    assert.equal(rithmicSideFromTransactionType("BUY"), "Buy")
    assert.equal(rithmicSideFromTransactionType("SELL"), "Sell")
    assert.equal(rithmicSideFromTransactionType("bogus"), null)
  })

  it("builds UTC executed_at from ssboe + usecs", () => {
    const iso = rithmicExecutedAtFromSsboe(1_700_000_000, 500_000)
    assert.equal(iso, new Date(1_700_000_000_500).toISOString())
  })

  it("stable fill id scopes fcm, ib, account, fill_id", () => {
    const id = stableRithmicFillId({
      fcmId: "F",
      ibId: "I",
      accountId: "A",
      fillId: "99",
    })
    assert.equal(id, "F|I|A|99")
  })

  it("checkpoint round-trip in provider_sync_state", () => {
    const merged = mergeRithmicFillCheckpoint(null, {
      indexFormat: "ssboe",
      lastSsboe: 1_700_000_000,
      lastUsecs: 100,
    })
    const read = readRithmicFillCheckpoint(merged)
    assert.deepEqual(read, {
      indexFormat: "ssboe",
      lastSsboe: 1_700_000_000,
      lastUsecs: 100,
    })
  })

  it("symbol root strips month code when present", () => {
    assert.equal(normalizeRithmicSymbolRoot("MNQH6"), "MNQ")
    assert.equal(normalizeRithmicSymbolRoot("ES"), "ES")
  })
})
