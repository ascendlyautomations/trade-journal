import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const sourcePath = path.join(process.cwd(), "lib/joinTradeRoom.ts")

describe("joinTradeRoom insert-or-reactivate contract", () => {
  const src = fs.readFileSync(sourcePath, "utf8")

  it("reactivates membership on duplicate insert (23505)", () => {
    assert.match(src, /error\.code === "23505"/)
    assert.match(src, /reactivateRoomMembership/)
    assert.match(src, /left_at: null/)
  })

  it("soft-reactivates when an inactive membership row exists", () => {
    assert.match(src, /existing\.left_at == null/)
    assert.match(src, /else if \(!alreadyActive\)/)
  })
})
