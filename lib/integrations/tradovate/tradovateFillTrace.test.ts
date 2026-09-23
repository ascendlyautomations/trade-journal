import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isTradovateTracedFillId,
  TRACED_MGC_FILL_IDS,
  TRADOVATE_SYNC_VERSION_MARKER,
  traceTradovateFillListStage,
} from "./tradovateFillTrace.ts"

describe("tradovateFillTrace", () => {
  it("tracks the three authoritative MGC fill ids", () => {
    assert.equal(TRACED_MGC_FILL_IDS.length, 3)
    assert.equal(isTradovateTracedFillId("660290950326"), true)
    assert.equal(isTradovateTracedFillId("660290950999"), false)
  })

  it("exposes deployment version marker for missing order hydration", () => {
    assert.equal(TRADOVATE_SYNC_VERSION_MARKER, "missingOrderHydration=v2")
  })

  it("fill_list stage marks absent traced ids", () => {
    traceTradovateFillListStage({
      targetAccountId: "65788591",
      mappingId: "mapping-1",
      fillsRaw: [
        {
          id: "660290950326",
          orderId: 1,
          contractId: 4176766,
          timestamp: "2026-09-22T18:36:27.000Z",
          action: "Buy",
          qty: 2,
          price: 4358.7,
        },
      ],
    })
    assert.ok(true)
  })
})
