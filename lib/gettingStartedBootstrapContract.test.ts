import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))
import { describe, it } from "node:test"
import { computeGettingStartedProgress, type GettingStartedSignals, } from "./gettingStartedChecklist.ts"
import { decodeGettingStartedSignalsRpc, } from "./gettingStartedSignalsRpc.ts"
import { mergeGettingStartedSignals, } from "./gettingStartedSignalsMerge.ts"
import { isGettingStartedRpcUnavailable, } from "./gettingStartedRpcAvailability.ts"
import { gettingStartedContractFixtures, } from "./gettingStartedContractFixtures.ts"
import { BackendV2RpcError } from "./backendV2/rpcClient.ts"
import assert from "node:assert/strict"

describe("gettingStartedContractFixtures", () => {
  for (const [name, fixture] of Object.entries(gettingStartedContractFixtures)) {
    it(`decodes ${name}`, () => {
      const decoded = decodeGettingStartedSignalsRpc(fixture.wire)
      assert.deepEqual(decoded, fixture.expected)
      const progress = computeGettingStartedProgress(decoded)
      assert.equal(typeof progress.completedCount, "number")
      assert.equal(progress.totalCount, 6)
    })
  }
})

describe("mergeGettingStartedSignals", () => {
  const baseline = gettingStartedContractFixtures.newUser.expected

  it("prefers warmed trades cache over RPC trade fields", () => {
    const merged = mergeGettingStartedSignals(baseline, {
      trade: {
        tradeCount: 4,
        hasPublicTrade: true,
        firstPrivateTradeId: "local-private",
      },
    })
    assert.equal(merged.tradeCount, 4)
    assert.equal(merged.hasPublicTrade, true)
    assert.equal(merged.firstPrivateTradeId, "local-private")
  })

  it("prefers session following count over RPC follow_count", () => {
    const merged = mergeGettingStartedSignals(baseline, {
      followCount: 3,
    })
    assert.equal(merged.followCount, 3)
  })

  it("prefers dashboard total_trade_count when trades cache is empty", () => {
    const merged = mergeGettingStartedSignals(baseline, {
      dashboardTradeCount: 7,
    })
    assert.equal(merged.tradeCount, 7)
  })

  it("prefers preloaded profile flags over RPC profile fields", () => {
    const merged = mergeGettingStartedSignals(baseline, {
      profile: {
        onboardingCompleted: true,
        hasSeenGettingStartedIntro: true,
        hasSeenOnboardingCompletePopup: true,
      },
    })
    assert.equal(merged.onboardingCompleted, true)
    assert.equal(merged.hasSeenGettingStartedIntro, true)
    assert.equal(merged.hasSeenOnboardingCompletePopup, true)
  })

  it("local overrides win over RPC baseline for final checklist", () => {
    const rpc = gettingStartedContractFixtures.hasAnyTrade.expected
    const merged = mergeGettingStartedSignals(rpc, {
      followCount: 2,
      trade: {
        tradeCount: 4,
        hasPublicTrade: true,
        firstPrivateTradeId: "local",
      },
    })
    assert.equal(merged.tradeCount, 4)
    assert.equal(merged.followCount, 2)
    assert.deepEqual(
      computeGettingStartedProgress(merged),
      computeGettingStartedProgress({
        ...rpc,
        tradeCount: 4,
        hasPublicTrade: true,
        followCount: 2,
      } satisfies GettingStartedSignals)
    )
  })
})

describe("isGettingStartedRpcUnavailable", () => {
  it("treats missing function as unavailable", () => {
    assert.equal(
      isGettingStartedRpcUnavailable(
        new BackendV2RpcError(
          "PGRST202",
          "Could not find the function rpc_v1_getting_started_signals",
          "rpc_v1_getting_started_signals"
        )
      ),
      true
    )
  })

  it("does not treat auth errors as missing RPC", () => {
    assert.equal(
      isGettingStartedRpcUnavailable(
        new BackendV2RpcError("42501", "not_authenticated", "rpc_v1_getting_started_signals")
      ),
      false
    )
  })
})

describe("Phase E — Getting Started RPC migration file", () => {
  it("defines SECURITY INVOKER rpc with auth.uid() gate", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../supabase/migrations/20260821021641_rpc_v1_getting_started_signals.sql"
      ),
      "utf8"
    )
    assert.match(sql, /security invoker/i)
    assert.match(sql, /auth\.uid\(\)/)
    assert.match(sql, /revoke all.*from public/i)
    assert.match(sql, /grant execute.*to authenticated/i)
  })
})
export {}
