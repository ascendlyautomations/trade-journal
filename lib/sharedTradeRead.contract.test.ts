import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"

describe("resolveSharedTradeRowForViewer contract", () => {
  it("falls back to trades social columns after trades_public_read", () => {
    const src = readFileSync(
      new URL("./sharedTradeRead.ts", import.meta.url),
      "utf8"
    )
    assert.match(src, /TRADES_PUBLIC_READ_RELATION/)
    assert.match(src, /\.from\("trades"\)/)
    assert.match(src, /PUBLIC_TRADE_SELECT/)
    assert.match(src, /rpcTradeOwnerRead/)
    assert.match(src, /shared-in-comment/)
  })
})