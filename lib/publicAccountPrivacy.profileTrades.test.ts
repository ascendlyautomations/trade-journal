import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  PUBLIC_TRADE_SELECT,
  TRADES_APP_SELECT,
  TRADES_PUBLIC_READ_RELATION,
  tradeListRelationForProfileViewer,
  tradeListSelectForProfileViewer,
} from "./publicAccountPrivacy.ts"

describe("profile public trade list reads", () => {
  it("uses trades_public_read for owner and visitor (public rows only)", () => {
    assert.equal(tradeListRelationForProfileViewer(true), TRADES_PUBLIC_READ_RELATION)
    assert.equal(tradeListRelationForProfileViewer(false), TRADES_PUBLIC_READ_RELATION)
  })

  it("selects only public-safe columns on the profile list surface", () => {
    assert.equal(tradeListSelectForProfileViewer(true), PUBLIC_TRADE_SELECT)
    assert.equal(tradeListSelectForProfileViewer(false), PUBLIC_TRADE_SELECT)
    assert.equal(PUBLIC_TRADE_SELECT.includes("is_initial_import"), false)
    assert.equal(TRADES_APP_SELECT.includes("is_initial_import"), true)
  })
})
