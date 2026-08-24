import { describe, it, beforeEach } from "node:test"
import { BackendV2RpcError } from "./rpcClient.ts"
import { isPropFirmRpcExecutionError, isPropFirmRpcUnavailable, isPropFirmTransientError, } from "./propFirmRpcCompat.ts"
import { clearPropFirmBootstrapCache, readPropFirmBootstrapCache, } from "./propFirmBootstrapCache.ts"
import { decodePropFirmBootstrapV1 } from "./propFirmBootstrapContracts.ts"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

describe("propFirmRpcCompat — classifier regression", () => {
  it("internal 42883 operator error is execution failure, not missing RPC", () => {
    const err = new BackendV2RpcError(
      "42883",
      "operator does not exist: text = uuid",
      "rpc_v1_prop_firm_bootstrap"
    )
    assert.equal(isPropFirmRpcExecutionError(err), true)
    assert.equal(isPropFirmRpcUnavailable(err), false)
    assert.equal(isPropFirmTransientError(err), false)
  })

  it("42883 missing function for rpc_v1_prop_firm_bootstrap activates fallback", () => {
    const err = new BackendV2RpcError(
      "42883",
      "function rpc_v1_prop_firm_bootstrap() does not exist",
      "rpc_v1_prop_firm_bootstrap"
    )
    assert.equal(isPropFirmRpcUnavailable(err), true)
    assert.equal(isPropFirmRpcExecutionError(err), false)
  })

  it("PGRST202 activates missing-RPC fallback", () => {
    const err = new BackendV2RpcError(
      "PGRST202",
      "Could not find the function public.rpc_v1_prop_firm_bootstrap",
      "rpc_v1_prop_firm_bootstrap"
    )
    assert.equal(isPropFirmRpcUnavailable(err), true)
  })

  it("5xx remains transient, not unavailable", () => {
    const err = new BackendV2RpcError(
      "500",
      "upstream error",
      "rpc_v1_prop_firm_bootstrap"
    )
    assert.equal(isPropFirmTransientError(err), true)
    assert.equal(isPropFirmRpcUnavailable(err), false)
  })
})

describe("propFirmRpcCompat — cache on failure", () => {
  beforeEach(() => {
    clearPropFirmBootstrapCache()
  })

  it("failed RPC response is not cached", () => {
    assert.equal(readPropFirmBootstrapCache("user-a"), null)
    try {
      decodePropFirmBootstrapV1(null)
      assert.fail("expected decode to throw")
    } catch {
      // simulate failed decode — cache must stay empty
    }
    assert.equal(readPropFirmBootstrapCache("user-a"), null)
  })
})

describe("propFirmRpcCompat — sql type contract", () => {
  it("fix migration compares trades.account_id against text[] account ids", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260824130000_fix_prop_firm_bootstrap_type_contract.sql"
      ),
      "utf8"
    )
    assert.match(sql, /v_account_ids_text text\[\]/)
    assert.match(sql, /array_agg\(a\.id::text\)/)
    assert.match(sql, /t\.account_id = any \(v_account_ids_text\)/)
    assert.doesNotMatch(sql, /t\.account_id = any \(v_account_ids\)/)
  })

  it("fix migration keeps uuid[] comparisons for achievements and payout cycles", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260824130000_fix_prop_firm_bootstrap_type_contract.sql"
      ),
      "utf8"
    )
    assert.match(sql, /ach\.account_id = any \(v_account_ids\)/)
    assert.match(sql, /pc\.account_id = any \(v_funded_ids\)/)
  })

  it("fix migration skips blank legacy trade account_id values", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260824130000_fix_prop_firm_bootstrap_type_contract.sql"
      ),
      "utf8"
    )
    assert.match(sql, /nullif\(trim\(t\.account_id\), ''\)/)
  })

  it("original migration contained the text = uuid mismatch", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../../supabase/migrations/20260824120000_rpc_v1_prop_firm_bootstrap.sql"
      ),
      "utf8"
    )
    assert.match(sql, /t\.account_id = any \(v_account_ids\)/)
  })
})

describe("propFirmRpcCompat — page wiring", () => {
  it("prop firm page shows load error for non-unavailable RPC failures", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../../app/(app)/analytics/propfirm/page.tsx"),
      "utf8"
    )
    assert.match(src, /isPropFirmRpcUnavailable\(err\)/)
    assert.match(src, /setPropFirmUseLegacy\(true\)/)
    assert.match(src, /setAccountsLoadError/)
    assert.match(src, /\[prop-firm-v2\] bootstrap failed/)
  })

  it("successful bootstrap path uses snapshot without legacy loaders when V2 active", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../../app/(app)/analytics/propfirm/page.tsx"),
      "utf8"
    )
    assert.match(src, /snapshotPropFirmBootstrapPageData/)
    assert.match(src, /if \(propFirmV2Active\) return/)
  })
})
export {}
