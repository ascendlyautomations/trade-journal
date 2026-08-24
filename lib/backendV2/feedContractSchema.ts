/**
 * Phase B2: Feed bootstrap RPC contract validators.
 * Validates wire shape/types — not server_time (volatile).
 */

import type {
  FeedBootstrapV1,
  FeedContentFilterV1,
  FeedItemKindV1,
  FeedItemV1,
} from "./contracts.ts"

export type FeedContractViolation = {
  path: string
  message: string
  expected?: string
  actual?: string
}

const FEED_KINDS: FeedItemKindV1[] = [
  "post",
  "profile_post",
  "reel",
  "achievement_post",
  "trade_card",
]

const FEED_FILTERS: FeedContentFilterV1[] = [
  "all",
  "trades",
  "reels",
  "posts",
  "achievements",
]

const FEED_SCOPES = ["following", "global"] as const

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function typeOf(value: unknown): string {
  if (value === null) return "null"
  if (Array.isArray(value)) return "array"
  return typeof value
}

function requireKeys(
  obj: Record<string, unknown>,
  keys: string[],
  prefix: string,
  out: FeedContractViolation[]
): void {
  for (const key of keys) {
    if (!(key in obj)) {
      out.push({ path: `${prefix}.${key}`, message: "missing required key" })
    }
  }
}

function requireType(
  value: unknown,
  expected: string,
  path: string,
  out: FeedContractViolation[]
): void {
  const actual = typeOf(value)
  if (actual !== expected) {
    out.push({ path, message: "type mismatch", expected, actual })
  }
}

/** Composite keyset cursor: ISO8601|kind|uuid (Phase B2). Legacy timestamp-only accepted on input. */
export function isCompositeFeedCursor(value: string): boolean {
  const parts = value.split("|")
  if (parts.length !== 3) return false
  const [ts, kind, id] = parts
  if (!ts || !kind || !id) return false
  if (!FEED_KINDS.includes(kind as FeedItemKindV1) && kind !== "trade_card") {
    return false
  }
  return /^[0-9a-f-]{36}$/i.test(id)
}

function validateFeedItem(item: FeedItemV1, index: number, out: FeedContractViolation[]): void {
  const prefix = `data.items[${index}]`
  if (!FEED_KINDS.includes(item.kind)) {
    out.push({
      path: `${prefix}.kind`,
      message: "unknown feed item kind",
      actual: String(item.kind),
    })
  }
  requireType(item.id, "string", `${prefix}.id`, out)
  requireType(item.created_at, "string", `${prefix}.created_at`, out)
  requireType(item.author_id, "string", `${prefix}.author_id`, out)
  requireType(item.payload, "object", `${prefix}.payload`, out)
}

function validateAuthorCard(
  author: unknown,
  path: string,
  out: FeedContractViolation[]
): void {
  if (!isObject(author)) {
    requireType(author, "object", path, out)
    return
  }
  requireType(author.id, "string", `${path}.id`, out)
  if ("username" in author && author.username !== null) {
    requireType(author.username, "string", `${path}.username`, out)
  }
  if ("avatar_url" in author && author.avatar_url !== null) {
    requireType(author.avatar_url, "string", `${path}.avatar_url`, out)
  }
}

/** Validates Feed bootstrap v1 wire contract (ignores meta.server_time). */
export function validateFeedBootstrapContract(
  raw: FeedBootstrapV1
): FeedContractViolation[] {
  const v: FeedContractViolation[] = []

  if (raw.meta.contract_version !== "v1") {
    v.push({
      path: "meta.contract_version",
      message: "must be v1",
      expected: "v1",
      actual: String(raw.meta.contract_version),
    })
  }

  requireType(raw.meta.viewer_id, "string", "meta.viewer_id", v)

  const data = raw.data
  requireKeys(
    data as unknown as Record<string, unknown>,
    [
      "scope",
      "content_filter",
      "items",
      "authors",
      "engagement",
      "stories",
      "story_authors",
      "next_cursor",
      "page_meta",
      "following_ids_echo",
    ],
    "data",
    v
  )

  if (!FEED_SCOPES.includes(data.scope)) {
    v.push({
      path: "data.scope",
      message: "invalid scope",
      expected: FEED_SCOPES.join("|"),
      actual: String(data.scope),
    })
  }

  if (!FEED_FILTERS.includes(data.content_filter)) {
    v.push({
      path: "data.content_filter",
      message: "invalid content_filter",
      expected: FEED_FILTERS.join("|"),
      actual: String(data.content_filter),
    })
  }

  requireType(data.items, "array", "data.items", v)
  requireType(data.authors, "object", "data.authors", v)
  requireType(data.engagement, "object", "data.engagement", v)
  requireType(data.stories, "array", "data.stories", v)
  requireType(data.story_authors, "object", "data.story_authors", v)
  requireType(data.following_ids_echo, "array", "data.following_ids_echo", v)

  if (data.next_cursor !== null) {
    requireType(data.next_cursor, "string", "data.next_cursor", v)
  }

  requireKeys(
    data.page_meta as unknown as Record<string, unknown>,
    ["limit", "returned", "has_more"],
    "data.page_meta",
    v
  )
  requireType(data.page_meta.limit, "number", "data.page_meta.limit", v)
  requireType(data.page_meta.returned, "number", "data.page_meta.returned", v)
  requireType(data.page_meta.has_more, "boolean", "data.page_meta.has_more", v)

  if (data.page_meta.returned !== data.items.length) {
    v.push({
      path: "data.page_meta.returned",
      message: "must equal items.length",
      expected: String(data.items.length),
      actual: String(data.page_meta.returned),
    })
  }

  if (data.page_meta.has_more && data.next_cursor === null) {
    v.push({
      path: "data.next_cursor",
      message: "must be set when page_meta.has_more is true",
    })
  }

  if (!data.page_meta.has_more && data.next_cursor !== null) {
    v.push({
      path: "data.next_cursor",
      message: "must be null when page_meta.has_more is false",
      actual: String(data.next_cursor),
    })
  }

  data.items.forEach((item, i) => validateFeedItem(item, i, v))

  for (const [authorId, author] of Object.entries(data.authors)) {
    validateAuthorCard(author, `data.authors.${authorId}`, v)
  }

  for (const [contentId, snap] of Object.entries(data.engagement)) {
    if (!isObject(snap)) continue
    requireType(snap.like_count, "number", `data.engagement.${contentId}.like_count`, v)
    requireType(
      snap.comment_count,
      "number",
      `data.engagement.${contentId}.comment_count`,
      v
    )
    requireType(
      snap.liked_by_viewer,
      "boolean",
      `data.engagement.${contentId}.liked_by_viewer`,
      v
    )
  }

  for (const story of data.stories) {
    requireType(story.id, "string", "data.stories[].id", v)
    requireType(story.user_id, "string", "data.stories[].user_id", v)
    requireType(story.image_url, "string", "data.stories[].image_url", v)
    requireType(story.created_at, "string", "data.stories[].created_at", v)
  }

  if (data.scope === "global" && data.stories.length > 0) {
    v.push({
      path: "data.stories",
      message: "global scope must return empty stories array",
      actual: String(data.stories.length),
    })
  }

  return v
}

/** Semantic compare for old vs new RPC regression (excludes volatile meta.server_time). */
export function compareFeedBootstrapSemantics(
  a: FeedBootstrapV1,
  b: FeedBootstrapV1
): FeedContractViolation[] {
  const v: FeedContractViolation[] = []

  const strip = (f: FeedBootstrapV1) => {
    const copy = JSON.parse(JSON.stringify(f)) as FeedBootstrapV1
    copy.meta.server_time = "FIXED"
    return copy
  }

  const sa = strip(a)
  const sb = strip(b)

  if (JSON.stringify(sa) !== JSON.stringify(sb)) {
    v.push({ path: "root", message: "semantic payload differs after stripping server_time" })
  }

  return v
}
