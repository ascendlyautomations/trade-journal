import { normalizeProfileUsername } from "../profileUsername.ts"

const ALIAS_SYMBOL = Symbol.for("tradetraxs.conversationThread.aliases")

type AliasStore = {
  byViewer: Map<string, Map<string, string>>
}

function aliasStore(): AliasStore {
  const g = globalThis as typeof globalThis & { [ALIAS_SYMBOL]?: AliasStore }
  if (!g[ALIAS_SYMBOL]) g[ALIAS_SYMBOL] = { byViewer: new Map() }
  return g[ALIAS_SYMBOL]
}

export function registerConversationThreadAlias(
  viewerId: string,
  alias: string,
  conversationId: string
): void {
  const viewer = viewerId.trim()
  const key = normalizeProfileUsername(alias)
  const cid = conversationId.trim()
  if (!viewer || !key || !cid) return
  const store = aliasStore()
  let map = store.byViewer.get(viewer)
  if (!map) {
    map = new Map()
    store.byViewer.set(viewer, map)
  }
  map.set(key, cid)
}

export function resolveConversationThreadAlias(
  viewerId: string,
  alias: string
): string | null {
  const viewer = viewerId.trim()
  const key = normalizeProfileUsername(alias)
  if (!viewer || !key) return null
  return aliasStore().byViewer.get(viewer)?.get(key) ?? null
}

export function clearConversationThreadAliases(viewerId?: string | null): void {
  if (!viewerId) {
    aliasStore().byViewer.clear()
    return
  }
  aliasStore().byViewer.delete(viewerId.trim())
}
