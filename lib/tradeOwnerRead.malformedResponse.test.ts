import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { asJsonObject } from "./supabaseProjectedQuery.ts"

/** Mirrors rpcTradesOwnerRows malformed-response handling (see tradeOwnerRead.ts). */
function parseOwnerRowsRpcData(data: unknown): { rows: unknown[]; error: Error | null } {
  if (!Array.isArray(data)) {
    return {
      rows: [],
      error: new Error("Invalid rpc_v1_trades_owner_rows response"),
    }
  }
  const rows = data
    .map((row) => asJsonObject(row))
    .filter((row): row is Record<string, unknown> => row != null)
  return { rows, error: null }
}

describe("trade owner rows RPC parsing", () => {
  it("surfaces malformed payloads as errors", () => {
    const { rows, error } = parseOwnerRowsRpcData({ bad: true })
    assert.equal(rows.length, 0)
    assert.ok(error)
  })

  it("accepts empty arrays", () => {
    const { rows, error } = parseOwnerRowsRpcData([])
    assert.deepEqual(rows, [])
    assert.equal(error, null)
  })
})
