/**
 * Per-viewer/per-conversation intentional-open read lifecycle.
 * Prevents duplicate mark-read from Strict Mode, alias resolution, or re-apply.
 */

export type ThreadBootstrapLoadMode =
  | "intentional-open"
  | "pagination"
  | "revalidate"
  | "cache-only"

type MarkReadState = "none" | "in-flight" | "committed"

type OpenLifecycle = {
  openId: number
  byConversation: Map<string, MarkReadState>
}

const lifecycles = new Map<string, OpenLifecycle>()
let globalOpenId = 0

function viewerKey(viewerId: string): string {
  return viewerId.trim()
}

function lifecycleFor(viewerId: string): OpenLifecycle {
  const key = viewerKey(viewerId)
  let entry = lifecycles.get(key)
  if (!entry) {
    entry = { openId: globalOpenId, byConversation: new Map() }
    lifecycles.set(key, entry)
  }
  return entry
}

function conversationKey(conversationId: string, openId: number): string {
  return `${openId}|${conversationId.trim()}`
}

/** Call on thread URL segment change — starts a new intentional-open lifecycle. */
export function beginThreadOpenLifecycle(viewerId: string): number {
  globalOpenId += 1
  const key = viewerKey(viewerId)
  lifecycles.set(key, { openId: globalOpenId, byConversation: new Map() })
  return globalOpenId
}

export function clearThreadReadLifecycle(viewerId?: string | null): void {
  if (!viewerId) {
    lifecycles.clear()
    return
  }
  lifecycles.delete(viewerKey(viewerId))
}

export function resolveThreadBootstrapMarkRead(input: {
  viewerId: string
  conversationId: string
  openId: number
  mode: ThreadBootstrapLoadMode
  authenticated?: boolean
}): boolean {
  if (input.authenticated === false) return false
  if (input.mode !== "intentional-open") return false

  const viewer = viewerKey(input.viewerId)
  const conversationId = input.conversationId.trim()
  if (!viewer || !conversationId) return false

  const lifecycle = lifecycles.get(viewer)
  if (!lifecycle || lifecycle.openId !== input.openId) return false

  const state = lifecycle.byConversation.get(
    conversationKey(conversationId, input.openId)
  )
  if (state === "committed" || state === "in-flight") return false
  return true
}

export function markThreadReadInFlight(
  viewerId: string,
  conversationId: string,
  openId: number
): void {
  const lifecycle = lifecycleFor(viewerId)
  lifecycle.byConversation.set(
    conversationKey(conversationId, openId),
    "in-flight"
  )
}

export function commitThreadMarkRead(
  viewerId: string,
  conversationId: string,
  openId: number
): void {
  const lifecycle = lifecycleFor(viewerId)
  lifecycle.byConversation.set(
    conversationKey(conversationId, openId),
    "committed"
  )
}

export function releaseThreadReadInFlight(
  viewerId: string,
  conversationId: string,
  openId: number
): void {
  const lifecycle = lifecycles.get(viewerKey(viewerId))
  if (!lifecycle) return
  const key = conversationKey(conversationId, openId)
  if (lifecycle.byConversation.get(key) === "in-flight") {
    lifecycle.byConversation.set(key, "none")
  }
}

/** @internal */
export function __resetThreadReadLifecycleForTests(): void {
  lifecycles.clear()
  globalOpenId = 0
}
