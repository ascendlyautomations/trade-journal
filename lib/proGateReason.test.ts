import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  PRO_LIMIT_REACHED_CODE,
  buildProLimitPayload,
  parseProLimitPayload,
  proGateSubtitle,
  proLimitKindFromLegacyCode,
} from "./proGateReason.ts"

describe("proGateReason", () => {
  it("maps legacy FREE_PLAN codes", () => {
    assert.equal(proLimitKindFromLegacyCode("FREE_PLAN_DAILY_TRADE_LIMIT"), "daily_trades")
    assert.equal(proLimitKindFromLegacyCode("FREE_PLAN_ACCOUNT_LIMIT"), "account_count")
  })

  it("builds PRO_LIMIT_REACHED payloads", () => {
    const payload = buildProLimitPayload("csv_import_cooldown")
    assert.equal(payload.code, PRO_LIMIT_REACHED_CODE)
    assert.equal(payload.limit, "csv_import_cooldown")
    assert.match(payload.message, /3 days/)
  })

  it("parses structured API errors", () => {
    const parsed = parseProLimitPayload({
      code: PRO_LIMIT_REACHED_CODE,
      limit: "daily_posts",
      message: "custom",
    })
    assert.ok(parsed)
    assert.equal(parsed?.limit, "daily_posts")
    assert.equal(parsed?.message, "custom")
  })

  it("parses legacy postgres exception strings", () => {
    const parsed = parseProLimitPayload({ message: "FREE_PLAN_DAILY_CLIP_LIMIT" })
    assert.equal(parsed?.limit, "daily_clips")
  })

  it("uses TradeTraxs Pro in feature subtitles", () => {
    assert.match(
      proGateSubtitle({ type: "feature", feature: "copy_trading" }),
      /TradeTraxs Pro/
    )
  })
})
