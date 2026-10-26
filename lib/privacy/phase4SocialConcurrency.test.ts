import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import {
  beginSocialMutation,
  isSocialMutationCurrent,
  rollbackSocialMutationIfCurrent,
  socialMutationKey,
} from "../socialMutationEpoch.ts"

describe("socialMutationEpoch", () => {
  it("ignores stale rollbacks after a newer mutation", () => {
    const key = socialMutationKey("test", "a", "b")
    const first = beginSocialMutation(key)
    beginSocialMutation(key)
    let rolled = false
    rollbackSocialMutationIfCurrent(key, first, () => {
      rolled = true
    })
    assert.equal(rolled, false)
    assert.equal(isSocialMutationCurrent(key, first), false)
  })

  it("applies rollback when the epoch is still current", () => {
    const key = socialMutationKey("test", "c")
    const epoch = beginSocialMutation(key)
    let rolled = false
    rollbackSocialMutationIfCurrent(key, epoch, () => {
      rolled = true
    })
    assert.equal(rolled, true)
  })
})

describe("phase 4 social concurrency contracts", () => {
  it("web like toggles use mutation epochs", () => {
    for (const file of [
      "lib/toggleContentLike.ts",
      "lib/reelEngagement.ts",
      "lib/commentLikes.ts",
    ]) {
      const src = fs.readFileSync(path.join(process.cwd(), file), "utf8")
      assert.match(src, /beginSocialMutation/)
      assert.match(src, /rollbackSocialMutationIfCurrent/)
    }
  })

  it("follow actions treat duplicate edges as success", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "lib/followActions.ts"),
      "utf8"
    )
    assert.match(src, /isUniqueViolation/)
    assert.match(src, /state: "following"/)
    assert.match(src, /state: "requested"/)
  })

  it("feed pagination merge dedupes items", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "app/(app)/feed/page.tsx"),
      "utf8"
    )
    assert.match(src, /dedupeFeedItems\(\[\.\.\.postsRef\.current/)
  })

  it("engagement tables enforce one like per user (migration baseline)", () => {
    const engagementMigration = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20260616150000_engagement_duplicate_submit_unique.sql"
      ),
      "utf8"
    )
    assert.match(engagementMigration, /likes_post_user_unique_idx/)
    assert.match(engagementMigration, /followers_pair_unique_idx/)

    const tradeLikes = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20260406120000_trade_likes_comments.sql"
      ),
      "utf8"
    )
    assert.match(tradeLikes, /unique \(trade_id, user_id\)/)
  })

  it("like notifications dedupe by unique indexes", () => {
    const sql = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20260624130000_notifications_like_deduplication.sql"
      ),
      "utf8"
    )
    assert.match(sql, /notifications_like_trade_unique_idx/)
    assert.match(sql, /notifications_like_post_unique_idx/)
  })
})

describe("dedupeFeedItems pagination boundary", () => {
  it("dedupes by feedKind:id key", () => {
    const src = fs.readFileSync(
      path.join(process.cwd(), "app/components/feed/feedPostHelpers.ts"),
      "utf8"
    )
    assert.match(src, /`\$\{item\.feedKind\}:\$\{item\.id\}`/)
    assert.match(src, /if \(seen\.has\(key\)\) continue/)
  })
})
