import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const root = process.cwd()

function read(rel: string) {
  return fs.readFileSync(path.join(root, rel), "utf8")
}

describe("feed following cand prototype (staging-only)", () => {
  it("documents per-followee lateral approach and verification harness", () => {
    const doc = read("supabase/staging/docs/FEED_FOLLOWING_CAND_OPTIMIZATION.md")
    assert.match(doc, /per-followee/)
    assert.match(doc, /v_scope = 'following'/)
    assert.match(doc, /57014/)
    assert.match(doc, /hxlcvffvyadlxcsqxxoy/)

    const explain = read("supabase/staging/verify/feed_following_cand_explain_analyze.sql")
    assert.match(explain, /explain \(analyze, buffers/)
    assert.match(explain, /BASELINE/)
    assert.match(explain, /PROPOSED/)
    assert.match(explain, /cross join lateral/i)

    const equiv = read("supabase/staging/verify/feed_following_cand_equivalence.sql")
    assert.match(equiv, /except all/i)
    assert.match(equiv, /_posts_cand_baseline/)
    assert.match(equiv, /_posts_cand_proposed/)

    const proto = read("supabase/staging/prototypes/feed_following_cand_per_followee.sql")
    assert.match(proto, /STAGING \/ LOCAL ONLY/)
    assert.match(proto, /unnest\(v_following\)/)
    assert.match(proto, /Global unchanged/)
  })

  it("includes forward migration draft for following cand (not deployed by this test)", () => {
    const migration = path.join(
      root,
      "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"
    )
    assert.ok(fs.existsSync(migration))
    const sql = fs.readFileSync(migration, "utf8")
    assert.match(sql, /post_merge/)
  })
})
