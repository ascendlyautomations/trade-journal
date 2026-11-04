import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  freePlanSlotSelectionRequired,
  freePlanTradeSlotsPending,
  parseFreePlanTradeSlotsEpoch,
} from "./freePlanAccountSlots.ts"
import { isProActiveForTradeSlots } from "./subscription.ts"

describe("TraxPro ↔ Free account slot transitions", () => {
  const fourAccounts = [
    { id: "1", can_add_trades: true },
    { id: "2", can_add_trades: true },
    { id: "3", can_add_trades: true },
    { id: "4", can_add_trades: false },
  ]

  it("is_pro=false forces Free trade slots even with active subscription", () => {
    assert.equal(
      isProActiveForTradeSlots({
        is_pro: false,
        subscription_status: "active",
      }),
      false
    )
  })

  it("requires modal after downgrade when epoch is ahead of confirmed", () => {
    const epochs = parseFreePlanTradeSlotsEpoch({
      free_plan_trade_slots_epoch: 2,
      free_plan_trade_slots_confirmed_epoch: 1,
    })
    assert.equal(freePlanTradeSlotsPending(4, epochs), true)
    assert.equal(
      freePlanSlotSelectionRequired(false, fourAccounts, epochs),
      true
    )
  })

  it("does not re-prompt after confirmation for the same downgrade epoch", () => {
    const epochs = parseFreePlanTradeSlotsEpoch({
      free_plan_trade_slots_epoch: 2,
      free_plan_trade_slots_confirmed_epoch: 2,
    })
    assert.equal(freePlanTradeSlotsPending(4, epochs), false)
    assert.equal(
      freePlanSlotSelectionRequired(false, fourAccounts, epochs),
      false
    )
  })

  it("simulates Pro → Free → Pro → Free generations", () => {
    let required = 0
    let confirmed = 0

    const proAccounts = fourAccounts.map((row) => ({
      ...row,
      can_add_trades: true,
    }))

    assert.equal(freePlanSlotSelectionRequired(true, proAccounts), false)

    required += 1
    let epochs = parseFreePlanTradeSlotsEpoch({
      free_plan_trade_slots_epoch: required,
      free_plan_trade_slots_confirmed_epoch: confirmed,
    })
    assert.equal(
      freePlanSlotSelectionRequired(false, proAccounts, epochs),
      true
    )

    confirmed = required
    epochs = parseFreePlanTradeSlotsEpoch({
      free_plan_trade_slots_epoch: required,
      free_plan_trade_slots_confirmed_epoch: confirmed,
    })
    const afterPick = fourAccounts.map((row, idx) => ({
      ...row,
      can_add_trades: idx < 3,
    }))
    assert.equal(
      freePlanSlotSelectionRequired(false, afterPick, epochs),
      false
    )

    assert.equal(freePlanSlotSelectionRequired(true, afterPick, epochs), false)

    required += 1
    confirmed = required
    epochs = parseFreePlanTradeSlotsEpoch({
      free_plan_trade_slots_epoch: required,
      free_plan_trade_slots_confirmed_epoch: confirmed,
    })
    const restoredPro = proAccounts
    assert.equal(
      freePlanSlotSelectionRequired(true, restoredPro, epochs),
      false
    )

    required += 1
    confirmed = required - 1
    epochs = parseFreePlanTradeSlotsEpoch({
      free_plan_trade_slots_epoch: required,
      free_plan_trade_slots_confirmed_epoch: confirmed,
    })
    assert.equal(
      freePlanSlotSelectionRequired(false, restoredPro, epochs),
      true
    )
  })
})
