import assert from "node:assert/strict"
import test from "node:test"
import {
  buildDashboardPropFirmSnapshot,
  propFirmModeAccountIdFromQuery,
  resolveDashboardPropFirmAccount,
  type DashboardPropFirmAccount,
} from "./dashboardPropFirmContext.ts"

function account(
  id: string,
  extra: Partial<DashboardPropFirmAccount> = {}
): DashboardPropFirmAccount {
  return {
    id,
    name: "Alpha Futures",
    account_size: "50000",
    category: "Prop Firm",
    mode: "eval",
    profit_target: 3000,
    max_drawdown: 2000,
    consistency: 30,
    winning_days: 5,
    winning_day_threshold: 100,
    ...extra,
  }
}

test("dashboard prop firm selection is one prop eval or funded account", () => {
  const rows = {
    eval: account("eval"),
    funded: account("funded", { mode: "funded", name: "Apex" }),
    live: account("live", { mode: "live" }),
    sim: account("sim", { mode: "sim" }),
    backtest: account("backtest", { mode: "backtest" }),
    personal: account("personal", { category: "Personal", mode: "eval" }),
  }

  assert.equal(resolveDashboardPropFirmAccount("all", rows), null)
  assert.equal(resolveDashboardPropFirmAccount("", rows), null)
  assert.equal(
    resolveDashboardPropFirmAccount("Alpha|50K|eval", rows)?.id,
    "eval"
  )
  assert.equal(
    resolveDashboardPropFirmAccount("Apex|50K|funded", rows)?.mode,
    "funded"
  )
  assert.equal(resolveDashboardPropFirmAccount("Live|50K|live", rows), null)
  assert.equal(resolveDashboardPropFirmAccount("Sim|50K|sim", rows), null)
  assert.equal(
    resolveDashboardPropFirmAccount("Backtest|50K|backtest", rows),
    null
  )
  assert.equal(
    resolveDashboardPropFirmAccount("Personal|50K|personal", rows),
    null
  )
})

test("prop firm mode query only accepts an owned eval or funded account id", () => {
  const accounts = [
    { id: "eval", mode: "eval" },
    { id: "funded", mode: "funded" },
    { id: "live-prop", mode: "live" },
  ]
  assert.equal(propFirmModeAccountIdFromQuery("eval", accounts), "eval")
  assert.equal(propFirmModeAccountIdFromQuery("funded", accounts), "funded")
  assert.equal(propFirmModeAccountIdFromQuery("missing", accounts), null)
  assert.equal(propFirmModeAccountIdFromQuery("live-prop", accounts), null)
  assert.equal(propFirmModeAccountIdFromQuery("", accounts), null)
})

test("snapshot uses existing prop firm metrics for the selected account", () => {
  const snapshot = buildDashboardPropFirmSnapshot(
    account("eval"),
    [
      { id: "1", pnl: 400, date: "2026-01-02" },
      { id: "2", pnl: -50, date: "2026-01-03" },
    ]
  )
  assert.equal(snapshot.phase, "eval")
  assert.equal(snapshot.accountId, "eval")
  assert.equal(snapshot.balanceLabel, "$50,350")
  assert.equal(snapshot.profitTarget?.remainingLabel, "$2,650 left")
  assert.ok(snapshot.drawdown)
  assert.equal(snapshot.winningDays?.label, "1 / 5")
})
