import assert from "node:assert/strict"
import { describe, it } from "node:test"

/** Mirrors iOS `BootstrapMetaV1.server_time: String` — object timestamps must not ship. */
function decodeOwnerComparisonMeta(meta: unknown): { server_time: string } {
  if (typeof meta !== "object" || meta === null) {
    throw new Error("invalid meta")
  }
  const serverTime = (meta as { server_time?: unknown }).server_time
  if (typeof serverTime !== "string") {
    throw new Error("server_time must be ISO string")
  }
  return { server_time: serverTime }
}

describe("rpc_v1_trade_detail_owner_comparison wire", () => {
  it("accepts ISO string server_time", () => {
    const meta = decodeOwnerComparisonMeta({
      contract_version: "v1",
      server_time: "2026-09-21T22:15:30.123Z",
      viewer_id: "11111111-1111-1111-1111-111111111111",
    })
    assert.equal(meta.server_time, "2026-09-21T22:15:30.123Z")
  })

  it("rejects jsonb timestamp object server_time", () => {
    assert.throws(
      () =>
        decodeOwnerComparisonMeta({
          contract_version: "v1",
          server_time: { type: "timestamptz" },
          viewer_id: "x",
        }),
      /ISO string/
    )
  })
})
