import { blockedPeerIds } from "@/lib/feedSuggestedTraders"
import { supabase } from "@/lib/supabaseClient"

export const USER_BLOCK_LIST_CHANGED_EVENT = "tt:user-block-list-changed"

const blockedPeerSet = new Set<string>()

export function getBlockedPeerIdsSnapshot(): ReadonlySet<string> {
  return blockedPeerSet
}

export function noteBlockedPeer(userId: string): void {
  const id = String(userId ?? "").trim()
  if (!id) return
  blockedPeerSet.add(id)
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent(USER_BLOCK_LIST_CHANGED_EVENT))
  }
}

export function noteUnblockedPeer(userId: string): void {
  const id = String(userId ?? "").trim()
  if (!id) return
  blockedPeerSet.delete(id)
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent(USER_BLOCK_LIST_CHANGED_EVENT))
  }
}

export function replaceBlockedPeerIds(ids: Iterable<string>): void {
  blockedPeerSet.clear()
  for (const id of ids) {
    const trimmed = String(id ?? "").trim()
    if (trimmed) blockedPeerSet.add(trimmed)
  }
}

export function subscribeBlockedPeerList(listener: () => void): () => void {
  if (typeof window === "undefined") return () => {}
  const handler = () => listener()
  window.addEventListener(USER_BLOCK_LIST_CHANGED_EVENT, handler)
  return () => window.removeEventListener(USER_BLOCK_LIST_CHANGED_EVENT, handler)
}

export async function loadBlockedPeerIdsForViewer(
  viewerId: string
): Promise<string[]> {
  const id = String(viewerId ?? "").trim()
  if (!id) return []
  const { data, error } = await supabase
    .from("user_blocks")
    .select("blocker_id, blocked_id")
    .or(`blocker_id.eq.${id},blocked_id.eq.${id}`)
  if (error) {
    console.error("[blockedPeersClient] load failed", error)
    return []
  }
  return blockedPeerIds(
    id,
    (data ?? []) as { blocker_id: string; blocked_id: string }[]
  )
}

export function isAuthorBlocked(authorUserId: string | null | undefined): boolean {
  const id = String(authorUserId ?? "").trim()
  if (!id) return false
  return blockedPeerSet.has(id)
}
