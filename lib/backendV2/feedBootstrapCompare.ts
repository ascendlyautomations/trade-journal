import type { FeedBootstrapV1 } from "./contracts.ts"

export type FeedBootstrapMismatch = {
  path: string
  rest: unknown
  rpc: unknown
}

function sortedIds(ids: string[]): string[] {
  return [...ids].map(String).filter(Boolean).sort()
}

/** Lightweight dual-run compare — item ids + engagement keys + stories. */
export function compareFeedBootstraps(
  rest: FeedBootstrapV1,
  rpc: FeedBootstrapV1
): FeedBootstrapMismatch[] {
  const mismatches: FeedBootstrapMismatch[] = []

  if (rest.data.scope !== rpc.data.scope) {
    mismatches.push({
      path: "scope",
      rest: rest.data.scope,
      rpc: rpc.data.scope,
    })
  }

  if (rest.data.content_filter !== rpc.data.content_filter) {
    mismatches.push({
      path: "content_filter",
      rest: rest.data.content_filter,
      rpc: rpc.data.content_filter,
    })
  }

  const restIds = sortedIds(rest.data.items.map((i) => i.id))
  const rpcIds = sortedIds(rpc.data.items.map((i) => i.id))
  if (JSON.stringify(restIds) !== JSON.stringify(rpcIds)) {
    mismatches.push({
      path: "items.ids",
      rest: restIds.slice(0, 20),
      rpc: rpcIds.slice(0, 20),
    })
  }

  const restEng = sortedIds(Object.keys(rest.data.engagement))
  const rpcEng = sortedIds(Object.keys(rpc.data.engagement))
  if (JSON.stringify(restEng) !== JSON.stringify(rpcEng)) {
    mismatches.push({
      path: "engagement.keys",
      rest: restEng.slice(0, 20),
      rpc: rpcEng.slice(0, 20),
    })
  }

  const restStories = sortedIds(rest.data.stories.map((s) => s.id))
  const rpcStories = sortedIds(rpc.data.stories.map((s) => s.id))
  if (JSON.stringify(restStories) !== JSON.stringify(rpcStories)) {
    mismatches.push({
      path: "stories.ids",
      rest: restStories,
      rpc: rpcStories,
    })
  }

  if (rest.data.page_meta.has_more !== rpc.data.page_meta.has_more) {
    mismatches.push({
      path: "page_meta.has_more",
      rest: rest.data.page_meta.has_more,
      rpc: rpc.data.page_meta.has_more,
    })
  }

  return mismatches
}

export function logFeedBootstrapMismatches(
  mismatches: FeedBootstrapMismatch[]
): void {
  if (!mismatches.length) {
    console.debug("[backendV2.feed] dual-run OK — no mismatches")
    return
  }
  console.warn("[backendV2.feed] dual-run mismatches", mismatches)
}
