import { describe, it, beforeEach } from "node:test"
import { decodePropFirmBootstrapV1, } from "./propFirmBootstrapContracts.ts"
import { groupPropFirmPayoutCyclesByAccountId, filterPropFirmBootstrapRowsByAccountIds, snapshotPropFirmBootstrapPageData, PropFirmBootstrapStaleError, } from "./propFirmBootstrapRepository.ts"
import { readPropFirmBootstrapCache, writePropFirmBootstrapCache, clearPropFirmBootstrapCache, invalidatePropFirmBootstrap, } from "./propFirmBootstrapCache.ts"
import { __resetPropFirmBootstrapFlightsForTests, } from "./propFirmBootstrapSingleFlight.ts"
import { isPropFirmRpcUnavailable, isPropFirmTransientError, isPropFirmRpcExecutionError, } from "./propFirmRpcCompat.ts"
import { BackendV2RpcError } from "./rpcClient.ts"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

const fixture = {
  meta: {
    contract_version: "v1",
    server_time: "2026-08-24T12:00:00.000Z",
    viewer_id: "user-a",
  },
  data: {
    accounts: [
      { id: "acc-1", name: "Funded A", mode: "Funded", category: "Prop Firm" },
      { id: "acc-2", name: "Eval B", mode: "Eval", category: "Prop Firm" },
    ],
    payout_cycles: [
      {
        id: "cyc-1",
        account_id: "acc-1",
        started_at: "2026-01-01T00:00:00.000Z",
        ended_at: null,
        cycle_start_balance: 50000,
        payout_amount: null,
        note: null,
        balance_before_payout: null,
        balance_after_payout: null,
        drawdown_behavior: null,
        drawdown_floor_after_payout: null,
        cycle_number: 1,
      },
    ],
    achievements: [
      { id: "ach-1", account_id: "acc-1", achievement_type: "prop_firm_payout" },
      { id: "ach-2", account_id: "acc-2", achievement_type: "passed_eval" },
    ],
    trades: [
      { id: "t-1", account_id: "acc-1", pnl: 100, trade_date: "2026-01-02" },
      { id: "t-2", account_id: "acc-2", pnl: -50, trade_date: "2026-01-03" },
    ],
  },
}

describe("propFirmBootstrap — contract", () => {
  it("decodes v1 payload sections", () => {
    const decoded = decodePropFirmBootstrapV1(fixture)
    assert.equal(decoded.data.accounts.length, 2)
    assert.equal(decoded.data.payout_cycles.length, 1)
    assert.equal(decoded.data.achievements.length, 2)
    assert.equal(decoded.data.trades.length, 2)
  })

  it("groups payout cycles set-wise by account id", () => {
    const grouped = groupPropFirmPayoutCyclesByAccountId(fixture.data.payout_cycles)
    assert.equal(grouped["acc-1"]?.length, 1)
    assert.equal(grouped["acc-2"], undefined)
  })

  it("filters achievements and trades by selected account ids", () => {
    const achievements = filterPropFirmBootstrapRowsByAccountIds(
      fixture.data.achievements,
      ["acc-2"]
    )
    const trades = filterPropFirmBootstrapRowsByAccountIds(fixture.data.trades, [
      "acc-2",
    ])
    assert.equal(achievements.length, 1)
    assert.equal(trades.length, 1)
  })

  it("snapshot scopes page data without cross-account leaks", () => {
    const all = snapshotPropFirmBootstrapPageData(decodePropFirmBootstrapV1(fixture))
    assert.equal(all.trades.length, 2)
    const one = snapshotPropFirmBootstrapPageData(
      decodePropFirmBootstrapV1(fixture),
      ["acc-1"]
    )
    assert.equal(one.trades.length, 1)
    assert.equal(one.achievements.length, 1)
    assert.equal(one.payoutCyclesByAccountId["acc-1"]?.length, 1)
  })

  it("handles empty accounts", () => {
    const empty = decodePropFirmBootstrapV1({
      meta: fixture.meta,
      data: { accounts: [], payout_cycles: [], achievements: [], trades: [] },
    })
    const snapshot = snapshotPropFirmBootstrapPageData(empty)
    assert.deepEqual(snapshot.trades, [])
    assert.deepEqual(snapshot.achievements, [])
  })
})

describe("propFirmBootstrap — cache", () => {
  beforeEach(() => {
    clearPropFirmBootstrapCache()
    __resetPropFirmBootstrapFlightsForTests()
  })

  it("isolates cache between viewers", () => {
    writePropFirmBootstrapCache("user-a", decodePropFirmBootstrapV1(fixture))
    assert.ok(readPropFirmBootstrapCache("user-a"))
    assert.equal(readPropFirmBootstrapCache("user-b"), null)
  })

  it("invalidates viewer-scoped cache entries", () => {
    writePropFirmBootstrapCache("user-a", decodePropFirmBootstrapV1(fixture))
    invalidatePropFirmBootstrap("user-a")
    assert.equal(readPropFirmBootstrapCache("user-a"), null)
  })

  it("clears cache on logout helper", () => {
    writePropFirmBootstrapCache("user-a", decodePropFirmBootstrapV1(fixture))
    clearPropFirmBootstrapCache()
    assert.equal(readPropFirmBootstrapCache("user-a"), null)
  })
})

describe("propFirmBootstrap — rpc compat", () => {
  it("treats PGRST202 missing RPC as unavailable", () => {
    const missing = new BackendV2RpcError(
      "PGRST202",
      "function missing",
      "rpc_v1_prop_firm_bootstrap"
    )
    assert.equal(isPropFirmRpcUnavailable(missing), true)
    assert.equal(isPropFirmTransientError(missing), false)
  })

  it("treats internal 42883 operator error as execution failure", () => {
    const operator = new BackendV2RpcError(
      "42883",
      "operator does not exist: text = uuid",
      "rpc_v1_prop_firm_bootstrap"
    )
    assert.equal(isPropFirmRpcExecutionError(operator), true)
    assert.equal(isPropFirmRpcUnavailable(operator), false)
    assert.equal(isPropFirmTransientError(operator), false)
  })

  it("treats 5xx as transient without legacy fan-out classification", () => {
    const transient = new BackendV2RpcError(
      "500",
      "server error",
      "rpc_v1_prop_firm_bootstrap"
    )
    assert.equal(isPropFirmRpcUnavailable(transient), false)
    assert.equal(isPropFirmTransientError(transient), true)
  })
})

describe("propFirmBootstrap — stale rejection", () => {
  it("exposes stale error type for late responses", () => {
    const err = new PropFirmBootstrapStaleError()
    assert.equal(err.name, "PropFirmBootstrapStaleError")
  })
})

describe("propFirmBootstrap — sql artifact", () => {
  it("fix migration uses text[] for trades account_id matching", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260824130000_fix_prop_firm_bootstrap_type_contract.sql"
      ),
      "utf8"
    )
    assert.match(sql, /security invoker/i)
    assert.match(sql, /auth\.uid\(\)/)
    assert.match(sql, /v_account_ids_text text\[\]/)
    assert.match(sql, /t\.account_id = any \(v_account_ids_text\)/)
    assert.match(sql, /grant execute on function public\.rpc_v1_prop_firm_bootstrap\(\) to authenticated/)
    assert.match(sql, /revoke all on function public\.rpc_v1_prop_firm_bootstrap\(\) from public/)
  })
})
export {}
