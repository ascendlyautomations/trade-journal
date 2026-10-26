import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import {
  beginSocialMutation,
  rollbackSocialMutationIfCurrent,
  socialMutationKey,
} from "../socialMutationEpoch.ts"

describe("phase 5 production resilience contracts", () => {
  it("trade owner read distinguishes RPC errors from missing rows", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "lib/tradeOwnerRead.ts"),
      "utf8"
    )
    assert.match(src, /rpcTradeOwnerReadResult/)
    assert.match(src, /reason: "rpc_error"/)
    assert.match(src, /reason: "not_found"/)
    assert.match(src, /reportCriticalOperationFailure/)
  })

  it("trades cache preserves data and records lastLoadError on fetch failure", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "lib/appDataCache.ts"),
      "utf8"
    )
    assert.match(src, /lastLoadError/)
    assert.match(src, /A failed fetch must never be cached as a valid empty history/)
    assert.match(src, /getTradesLoadError/)
  })

  it("dashboard warm reports critical failures instead of silent catch", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "lib/dataPrefetch.ts"),
      "utf8"
    )
    assert.match(src, /reportCriticalOperationFailure/)
    assert.doesNotMatch(src, /ensureTradesLoaded\(supabase, id\)\.catch\(\(\) => \[\]\)/)
  })

  it("psychology journal does not silently fall back when RPC returns no rows for known ids", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "lib/psychology/reports/journalTrades.ts"),
      "utf8"
    )
    assert.match(src, /ids\.length > 0 && rows\.length === 0/)
  })

  it("broker persist surfaces trade write failures", () => {
    const src = fs.readFileSync(
      path.join(
        process.cwd(),
        "lib/integrations/tradovate/persistBrokerTrades.ts"
      ),
      "utf8"
    )
    assert.match(src, /tradeWriteFailures/)
    const sync = fs.readFileSync(
      path.join(
        process.cwd(),
        "lib/integrations/tradovate/syncTradovateBrokerAccount.ts"
      ),
      "utf8"
    )
    assert.match(sync, /tradePersistIncomplete/)
  })

  it("iOS logs critical payout RPC failures", () => {
    const src = fs.readFileSync(
      path.join(
        process.cwd(),
        "native-ios/TradeTraxs/TradeTraxs/Data/Repositories/DefaultTradeRepository.swift"
      ),
      "utf8"
    )
    assert.match(src, /CriticalOperationLog/)
    assert.match(src, /delete_account_payout_entry/)
    assert.match(src, /record_account_payout/)
  })
})

describe("criticalOperationTelemetry dedupe", () => {
  it("rolls back only current social mutations (phase 4 guard reused)", () => {
    const key = socialMutationKey("test", "phase5")
    const stale = beginSocialMutation(key)
    beginSocialMutation(key)
    let rolled = false
    rollbackSocialMutationIfCurrent(key, stale, () => {
      rolled = true
    })
    assert.equal(rolled, false)
  })
})
