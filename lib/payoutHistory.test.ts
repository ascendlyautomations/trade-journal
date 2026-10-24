import assert from "node:assert/strict"
import test from "node:test"
import {
  isLiveWithdrawalHistoryItem,
  isPropPayoutHistoryItem,
  payoutAchievementsMissingFromHistory,
  type PayoutHistoryItem,
  type UnmatchedPayoutAchievement,
} from "@/lib/payoutHistory"

function item(source: PayoutHistoryItem["source"]): PayoutHistoryItem {
  return {
    id: "ledger:past",
    amount: 1500,
    dateMs: Date.parse("2026-08-15T12:00:00.000Z"),
    payoutDate: "2026-08-15",
    accountId: "acct",
    ledgerEntryId: "past",
    source,
    note: "Prop Firm Payout",
    imageUrl: null,
    cycle: null,
    isEditable: true,
  }
}

test("past eval prop ledger payouts count as prop payouts", () => {
  assert.equal(
    isPropPayoutHistoryItem(item("otherLedger"), {
      id: "acct",
      category: "Prop Firm",
      mode: "Eval",
    }),
    true
  )
})

test("live ledger withdrawals stay out of prop payouts", () => {
  assert.equal(
    isPropPayoutHistoryItem(item("liveLedger"), {
      id: "acct",
      category: "Prop Firm",
      mode: "Live",
    }),
    false
  )
})

function cycleItem(amount: number, accountId: string, date: string, cycleId: string): PayoutHistoryItem {
  return {
    id: `cycle:${cycleId}`,
    amount,
    dateMs: Date.parse(`${date}T19:14:17.000Z`),
    payoutDate: null,
    accountId,
    ledgerEntryId: null,
    source: "fundedCycle",
    note: null,
    imageUrl: null,
    cycle: null,
    isEditable: false,
  }
}

function achievement(overrides: Partial<UnmatchedPayoutAchievement>): UnmatchedPayoutAchievement {
  return {
    id: "8b27e327-6a5f-4d5f-b0cb-48a402361325",
    achievementType: "live_trading_payout",
    title: "First Payout",
    amount: 585.95,
    achievedAt: "2026-04-13T00:00:00.000Z",
    createdAt: "2026-06-19T00:00:00.000Z",
    accountId: null,
    linkedCycleId: null,
    linkedEntryId: null,
    ...overrides,
  }
}

test("a payout achievement with no withdrawal record is added", () => {
  const added = payoutAchievementsMissingFromHistory([achievement({})], [])
  assert.equal(added.length, 1)
  assert.equal(added[0]?.id, "achievement:8b27e327-6a5f-4d5f-b0cb-48a402361325")
  assert.equal(added[0]?.amount, 585.95)
  assert.equal(added[0]?.source, "achievementLive")
  assert.equal(added[0]?.note, "First Payout")
  assert.equal(isLiveWithdrawalHistoryItem(added[0]!, undefined), true)
  assert.equal(isPropPayoutHistoryItem(added[0]!, undefined), false)
})

test("a prop achievement already saved as a payout cycle is not added again", () => {
  const recorded = cycleItem(
    954.48,
    "4ae02279-bd83-44c6-9309-ec1d70e9c415",
    "2026-10-23",
    "fe5ed60f-2c40-4817-aac1-4341ca742b22"
  )
  const added = payoutAchievementsMissingFromHistory(
    [
      achievement({
        id: "9ee1b915-c604-45a3-b667-fc801ede252c",
        achievementType: "prop_firm_payout",
        title: "Shmacked a payout",
        amount: 954.4799999999999,
        achievedAt: "2026-10-23T19:13:06.000Z",
        accountId: "4ae02279-bd83-44c6-9309-ec1d70e9c415",
        linkedCycleId: "16455105-0dae-40c2-892d-e2d83c5c6609",
      }),
    ],
    [recorded]
  )
  assert.equal(added.length, 0)
})

test("a prop achievement with no payout record is a prop payout", () => {
  const added = payoutAchievementsMissingFromHistory(
    [
      achievement({
        achievementType: "prop_firm_payout",
        title: "Prop Firm Payout",
        amount: 1500,
        accountId: "eval-account",
      }),
    ],
    []
  )
  assert.equal(added.length, 1)
  assert.equal(added[0]?.source, "achievementProp")
  assert.equal(isPropPayoutHistoryItem(added[0]!, undefined), true)
})
