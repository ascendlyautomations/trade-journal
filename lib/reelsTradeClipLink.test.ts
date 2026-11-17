import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const dir = dirname(fileURLToPath(import.meta.url))

describe("reels trade-clip link helpers", () => {
  it("exports eligibility fetchers and linkExistingReelToTrade", () => {
    const src = readFileSync(join(dir, "reels.ts"), "utf8")
    assert.match(src, /export async function fetchTradeIdsWithAttachedReels/)
    assert.match(src, /export async function fetchUnattachedReelsForUser/)
    assert.match(src, /export async function fetchPublicTradesEligibleForReelLink/)
    assert.match(src, /export async function linkExistingReelToTrade/)
    assert.match(src, /includingReelId/)
    assert.match(src, /includingTradeId/)
    assert.match(src, /already linked to another trade/)
    assert.match(src, /already has a clip attached/)
  })
})
