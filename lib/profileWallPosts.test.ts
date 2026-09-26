import { describe, it } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import {
  PROFILE_WALL_POSTS_PAGE_SIZE,
  PROFILE_WALL_POST_SELECT,
  canStartProfileWallPostsLoad,
  isCurrentProfileWallPostsRequest,
  mergeProfileWallPosts,
  patchProfileWallPost,
  profileWallPostsBeforeCursorFilter,
  removeProfileWallPost,
  sliceProfileWallPostsPage,
  upsertProfileWallPost,
} from "./profileWallPosts.ts"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

type Row = {
  id: string
  user_id: string
  content: string
  created_at: string
  is_pinned?: boolean | null
  image_url?: string | null
}

function row(
  id: string,
  createdAt: string,
  pinned = false,
  userId = "owner"
): Row {
  return {
    id,
    user_id: userId,
    content: id,
    created_at: createdAt,
    is_pinned: pinned,
    image_url: null,
  }
}

describe("profile wall posts pagination", () => {
  it("uses an explicit projection and a bounded page", () => {
    assert.equal(PROFILE_WALL_POSTS_PAGE_SIZE, 12)
    assert.equal(PROFILE_WALL_POST_SELECT.includes("*"), false)
    assert.match(PROFILE_WALL_POST_SELECT, /content/)
    assert.match(PROFILE_WALL_POST_SELECT, /image_url/)
    assert.match(PROFILE_WALL_POST_SELECT, /room_id/)
    assert.equal(PROFILE_WALL_POST_SELECT.includes("image_crop"), false)
  })

  it("returns no rows and is exhausted for an empty wall", () => {
    const page = sliceProfileWallPostsPage([], null, 12)
    assert.deepEqual(page.rows, [])
    assert.equal(page.hasMore, false)
    assert.equal(page.cursor, null)
  })

  it("returns a short wall in one page", () => {
    const posts = [
      row("b", "2026-01-02T00:00:00.000Z"),
      row("a", "2026-01-03T00:00:00.000Z"),
    ]
    const page = sliceProfileWallPostsPage(posts, null, 12)
    assert.deepEqual(
      page.rows.map((item) => item.id),
      ["a", "b"]
    )
    assert.equal(page.hasMore, false)
  })

  it("stops after an exact page", () => {
    const posts = Array.from({ length: 12 }, (_, index) =>
      row(`p${String(index).padStart(2, "0")}`, `2026-01-${String(28 - index).padStart(2, "0")}T00:00:00.000Z`)
    )
    const page = sliceProfileWallPostsPage(posts, null, 12)
    assert.equal(page.rows.length, 12)
    assert.equal(page.hasMore, false)
  })

  it("pages pinned posts before newer unpinned posts", () => {
    const posts = [
      row("new", "2026-03-01T00:00:00.000Z", false),
      row("pin-old", "2026-01-01T00:00:00.000Z", true),
      row("mid", "2026-02-01T00:00:00.000Z", false),
    ]
    const page = sliceProfileWallPostsPage(posts, null, 2)
    assert.deepEqual(
      page.rows.map((item) => item.id),
      ["pin-old", "new"]
    )
    assert.equal(page.hasMore, true)
    const next = sliceProfileWallPostsPage(posts, page.cursor, 2)
    assert.deepEqual(
      next.rows.map((item) => item.id),
      ["mid"]
    )
    assert.equal(next.hasMore, false)
  })

  it("breaks equal timestamps by id descending and does not repeat rows", () => {
    const posts = [
      row("a", "2026-01-01T00:00:00.000Z"),
      row("c", "2026-01-01T00:00:00.000Z"),
      row("b", "2026-01-01T00:00:00.000Z"),
    ]
    const first = sliceProfileWallPostsPage(posts, null, 2)
    const second = sliceProfileWallPostsPage(posts, first.cursor, 2)
    const ids = [...first.rows, ...second.rows].map((item) => item.id)
    assert.deepEqual(ids, ["c", "b", "a"])
    assert.equal(new Set(ids).size, 3)
    assert.equal(second.hasMore, false)
  })

  it("walks multiple pages without gaps", () => {
    const posts = Array.from({ length: 25 }, (_, index) =>
      row(
        `id-${String(index).padStart(2, "0")}`,
        new Date(Date.UTC(2026, 0, 1, 0, 0, index)).toISOString()
      )
    )
    const seen: string[] = []
    let cursor = null as ReturnType<typeof sliceProfileWallPostsPage>["cursor"]
    let pages = 0
    let hasMore = true
    while (hasMore && pages < 10) {
      const page = sliceProfileWallPostsPage(posts, cursor, 12)
      seen.push(...page.rows.map((item) => item.id))
      cursor = page.cursor
      hasMore = page.hasMore
      pages += 1
    }
    assert.equal(pages, 3)
    assert.equal(seen.length, 25)
    assert.equal(new Set(seen).size, 25)
    assert.equal(seen[0], "id-24")
    assert.equal(seen[24], "id-00")
  })

  it("ignores a second load-more while one page is in flight", () => {
    assert.equal(
      canStartProfileWallPostsLoad({
        inFlight: true,
        hasMore: true,
        mode: "more",
      }),
      false
    )
    assert.equal(
      canStartProfileWallPostsLoad({
        inFlight: false,
        hasMore: false,
        mode: "more",
      }),
      false
    )
    assert.equal(
      canStartProfileWallPostsLoad({
        inFlight: false,
        hasMore: true,
        mode: "more",
      }),
      true
    )
  })

  it("drops a page that belongs to a different profile", () => {
    assert.equal(isCurrentProfileWallPostsRequest("user-a", "user-b"), false)
    assert.equal(isCurrentProfileWallPostsRequest("user-a", "user-a"), true)
    assert.equal(isCurrentProfileWallPostsRequest("user-a", null), false)
  })

  it("prepends a published post without duplicating it", () => {
    const existing = [row("old", "2026-01-01T00:00:00.000Z")]
    const created = row("new", "2026-02-01T00:00:00.000Z")
    const once = upsertProfileWallPost(existing, created)
    const twice = upsertProfileWallPost(once, created)
    assert.deepEqual(
      twice.map((item) => item.id),
      ["new", "old"]
    )
  })

  it("keeps a new unpinned post below pinned posts", () => {
    const existing = [row("pin", "2026-01-01T00:00:00.000Z", true)]
    const created = row("new", "2026-06-01T00:00:00.000Z", false)
    assert.deepEqual(
      upsertProfileWallPost(existing, created).map((item) => item.id),
      ["pin", "new"]
    )
  })

  it("patches an edit by id and removes a delete by id", () => {
    const posts = [row("a", "2026-01-02T00:00:00.000Z"), row("b", "2026-01-01T00:00:00.000Z")]
    const edited = patchProfileWallPost(posts, "b", { content: "updated" })
    assert.equal(edited[1]?.content, "updated")
    assert.deepEqual(
      edited.map((item) => item.id),
      ["a", "b"]
    )
    assert.deepEqual(
      removeProfileWallPost(edited, "a").map((item) => item.id),
      ["b"]
    )
  })

  it("merges the next page without duplicating the boundary row", () => {
    const first = [row("a", "2026-01-03T00:00:00.000Z")]
    const incoming = [
      row("a", "2026-01-03T00:00:00.000Z"),
      row("b", "2026-01-02T00:00:00.000Z"),
    ]
    assert.deepEqual(
      mergeProfileWallPosts(first, incoming).map((item) => item.id),
      ["a", "b"]
    )
  })

  it("builds a keyset filter instead of an offset", () => {
    const filter = profileWallPostsBeforeCursorFilter(
      "2026-01-01T00:00:00.000Z",
      "abc"
    )
    assert.match(filter, /created_at\.lt/)
    assert.match(filter, /id\.lt/)
    assert.equal(filter.includes("offset"), false)
  })

  it("keeps owner and visitor on the same user-scoped select", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "profileWallPosts.ts"),
      "utf8"
    )
    assert.match(src, /\.eq\("user_id", userId\)/)
    assert.doesNotMatch(src, /select\("\*"\)/)
    const page = fs.readFileSync(
      path.join(__dirname, "../app/profile/[id]/page.tsx"),
      "utf8"
    )
    assert.equal(page.includes('.from("profile_posts")\n        .select("*")'), false)
    assert.match(page, /fetchProfileWallPostsPage/)
    assert.match(page, /fetchProfileWallPostById/)
    assert.doesNotMatch(
      page,
      /from\("profile_posts"\)[\s\S]{0,80}\.select\("\*"\)/
    )
  })
})
