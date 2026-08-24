/**
 * Messaging bootstrap repositories (REST + RPC).
 * Flag OFF → production unchanged. Flag ON → V2 RPC with V1 fallback.
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import {
  fetchUserDmConversations,
  type DmConversationRow,
} from "@/lib/shareToConversations"
import { fetchUnreadCountsForConversations } from "@/lib/messageUnread"
import { fetchMutedConversationIds } from "@/lib/conversationMemberPreferences"
import { markMessageNotificationsRead } from "@/lib/messageNotificationReadSync.ts"
import type { MessagesBootstrapProviding } from "./adapters.ts"
import {
  decodeMessagesBootstrapV1,
  type MessagesBootstrapV1,
  type MessagingConversationV1,
  type MessagingParticipantV1,
} from "./contracts.ts"
import {
  compareMessagingBootstraps,
  logMessagingBootstrapMismatches,
} from "./messagingBootstrapCompare.ts"
import {
  invalidateMessagingBootstrap,
  messagingBootstrapCacheKey,
  readMessagingBootstrapCache,
  writeMessagingBootstrapCache,
} from "./messagingBootstrapCache.ts"
import {
  beginMessagingBootstrapFlight,
  getMessagingBootstrapFlight,
} from "./messagingBootstrapSingleFlight.ts"
import { isBackendV2Enabled } from "./flags.ts"
import {
  BackendV2RpcClient,
  createSupabaseBackendV2Transport,
} from "./rpcClient.ts"
import {
  measureAsync,
  recordBackendV2Telemetry,
  utf8ByteLength,
} from "./telemetry.ts"
import { BackendV2RpcNames } from "./versioning.ts"
import {
  isMessagingV2Unavailable,
  v1CursorFromComposite,
} from "./messagingRpcCompat.ts"
import {
  clearMessagingV2UnavailableCache,
  isMessagingV2CachedUnavailable,
  markMessagingV2Unavailable,
} from "./messagingV2Availability.ts"

export const MESSAGING_INBOX_PAGE_SIZE = 40

export type MessagingBootstrapInput = {
  cursor?: string | null
  limit?: number
  /** Inbox intentional open — V2 marks message notifications in-RPC; V1 uses PATCH fallback. */
  markMessageNotificationsRead?: boolean
}

export type MessagingRpcVersion = "v2" | "v1"

export type MessagingRpcLoadResult = {
  bootstrap: MessagesBootstrapV1
  rpcVersion: MessagingRpcVersion
}

export { isMessagingV2Unavailable, v1CursorFromComposite } from "./messagingRpcCompat.ts"

function mapParticipants(
  row: DmConversationRow
): MessagingParticipantV1[] {
  return row.participants.map((p) => ({
    user_id: p.user_id,
    username: p.profiles?.username ?? null,
    display_name: p.profiles?.name ?? p.profiles?.username ?? null,
    avatar_url: p.profiles?.avatar_url ?? null,
  }))
}

function toMessagingConversation(
  row: DmConversationRow,
  unread: number,
  muted: boolean
): MessagingConversationV1 {
  return {
    id: row.id,
    is_group: row.is_group,
    is_pinned: row.is_pinned,
    name: row.name,
    avatar_url: row.avatar_url,
    last_message: row.last_message,
    last_message_at: row.last_message_at,
    unread_count: muted ? 0 : unread,
    muted,
    participants: mapParticipants(row),
  }
}

/** Map bootstrap conversation → DmConversationRow for existing inbox mapper. */
export function messagingConversationToDmRow(
  conv: MessagingConversationV1
): DmConversationRow {
  return {
    id: conv.id,
    is_group: conv.is_group,
    is_pinned: conv.is_pinned,
    name: conv.name,
    avatar_url: conv.avatar_url,
    last_message: conv.last_message,
    last_message_at: conv.last_message_at,
    participants: conv.participants.map((p) => ({
      user_id: p.user_id,
      profiles: {
        id: p.user_id,
        username: p.username,
        avatar_url: p.avatar_url,
        name: p.display_name,
      },
    })),
  }
}

export class MessagingRestBootstrapRepository
  implements MessagesBootstrapProviding
{
  constructor(
    private readonly client: SupabaseClient,
    private readonly userId: string
  ) {}

  async loadMessagesBootstrap(
    input?: MessagingBootstrapInput
  ): Promise<MessagesBootstrapV1> {
    const uid = this.userId
    const limit = Math.max(
      1,
      Math.min(input?.limit ?? MESSAGING_INBOX_PAGE_SIZE, 80)
    )
    const serverTime = new Date().toISOString()

    const { rows, error } = await fetchUserDmConversations(this.client, uid)
    if (error) throw error

    const convoIds = rows.map((r) => r.id)
    const [cursorCounts, mutedIds] = await Promise.all([
      fetchUnreadCountsForConversations(uid, convoIds),
      fetchMutedConversationIds(uid, convoIds),
    ])

    const sorted = [...rows].sort((a, b) => {
      if (a.is_pinned !== b.is_pinned) return a.is_pinned ? -1 : 1
      return (
        new Date(b.last_message_at || 0).getTime() -
        new Date(a.last_message_at || 0).getTime()
      )
    })

    const page = sorted.slice(0, limit)
    const hasMore = sorted.length > limit
    const conversations = page.map((row) =>
      toMessagingConversation(
        row,
        cursorCounts[row.id] ?? 0,
        mutedIds.has(row.id)
      )
    )

    let dmUnreadTotal = 0
    for (const id of convoIds) {
      if (mutedIds.has(id)) continue
      dmUnreadTotal += cursorCounts[id] ?? 0
    }

    const peers: MessagesBootstrapV1["data"]["peers"] = {}
    for (const conv of conversations) {
      for (const p of conv.participants) {
        if (p.user_id === uid) continue
        if (!peers[p.user_id]) {
          peers[p.user_id] = {
            id: p.user_id,
            username: p.username,
            display_name: p.display_name,
            avatar_url: p.avatar_url,
          }
        }
      }
    }

    const last = conversations[conversations.length - 1]
    return {
      meta: {
        contract_version: "v1",
        server_time: serverTime,
        viewer_id: uid,
      },
      data: {
        conversations,
        peers,
        dm_unread_total: dmUnreadTotal,
        muted_ids: [...mutedIds].map(String),
        next_cursor:
          hasMore && last?.last_message_at ? last.last_message_at : null,
        page_meta: {
          limit,
          returned: conversations.length,
          has_more: hasMore,
        },
      },
    }
  }
}

export class MessagingRpcBootstrapRepository {
  private readonly client: BackendV2RpcClient
  private readonly supabase: SupabaseClient
  private readonly userId: string

  constructor(supabase: SupabaseClient, userId: string) {
    this.supabase = supabase
    this.userId = userId
    this.client = new BackendV2RpcClient({
      transport: createSupabaseBackendV2Transport(supabase),
    })
  }

  async loadMessagesBootstrap(
    input?: MessagingBootstrapInput
  ): Promise<MessagingRpcLoadResult> {
    const limit = input?.limit ?? MESSAGING_INBOX_PAGE_SIZE
    const cursor = input?.cursor?.trim() || null
    const markRead = input?.markMessageNotificationsRead === true

    const loadV1 = async (): Promise<MessagingRpcLoadResult> => {
      const bootstrap = await this.loadMessagesBootstrapV1(input)
      if (markRead && !cursor) {
        const marked = await markMessageNotificationsRead(
          this.userId,
          "page-open",
          this.supabase
        )
        bootstrap.data.message_notifications_marked_read = marked
      }
      return { bootstrap, rpcVersion: "v1" }
    }

    if (isMessagingV2CachedUnavailable()) {
      return loadV1()
    }

    try {
      const bootstrap = await this.client.callKnown(
        BackendV2RpcNames.messaging,
        decodeMessagesBootstrapV1,
        {
          args: {
            p_limit: limit,
            p_cursor: cursor,
            p_mark_message_notifications_read: markRead,
          },
          flagName: "backendV2.messages",
          cacheMiss: true,
        }
      )
      clearMessagingV2UnavailableCache()
      return { bootstrap, rpcVersion: "v2" }
    } catch (err) {
      if (!isMessagingV2Unavailable(err)) throw err
      markMessagingV2Unavailable()
      return loadV1()
    }
  }

  private async loadMessagesBootstrapV1(
    input?: MessagingBootstrapInput
  ): Promise<MessagesBootstrapV1> {
    const limit = input?.limit ?? MESSAGING_INBOX_PAGE_SIZE
    const cursor = input?.cursor?.trim() || null
    const v1Args: Record<string, unknown> = { p_limit: limit }
    if (cursor) {
      v1Args.p_cursor = v1CursorFromComposite(cursor)
    }
    return this.client.callKnown(
      BackendV2RpcNames.messagingV1,
      decodeMessagesBootstrapV1,
      {
        args: v1Args,
        flagName: "backendV2.messages",
        cacheMiss: true,
      }
    )
  }
}

export type MessagingBootstrapLoadResult = {
  bootstrap: MessagesBootstrapV1
  source: "rpc" | "rest" | "cache"
  rpcVersion: MessagingRpcVersion | null
  dualRunMismatches: number
  rpcRequestCount: number
  durationMs: number
  payloadBytes: number
  cacheHit: boolean
}

export async function loadMessagingBootstrapForUser(
  client: SupabaseClient,
  userId: string,
  options?: MessagingBootstrapInput & {
    force?: boolean
    caller?: string
    markMessageNotificationsRead?: boolean
  }
): Promise<MessagingBootstrapLoadResult> {
  const uid = userId.trim()
  if (!uid) throw new Error("loadMessagingBootstrapForUser requires userId")
  if (!isBackendV2Enabled("messages")) {
    throw new Error(
      "loadMessagingBootstrapForUser requires backendV2.messages flag ON"
    )
  }

  const cursor = options?.cursor?.trim() || null
  const limit = options?.limit ?? MESSAGING_INBOX_PAGE_SIZE
  const needsMarkRead = options?.markMessageNotificationsRead === true
  const key = messagingBootstrapCacheKey({ userId: uid, cursor })

  if (options?.force) {
    invalidateMessagingBootstrap(uid)
  }

  if (!options?.force && !cursor && !needsMarkRead) {
    const cached = readMessagingBootstrapCache(key)
    if (cached) {
      return {
        bootstrap: cached,
        source: "cache",
        rpcVersion: null,
        dualRunMismatches: 0,
        rpcRequestCount: 0,
        durationMs: 0,
        payloadBytes: 0,
        cacheHit: true,
      }
    }
    const existing = getMessagingBootstrapFlight<MessagingBootstrapLoadResult>(key)
    if (existing) return existing
  }

  return beginMessagingBootstrapFlight(key, uid, async () => {
    if (!options?.force && !cursor && !needsMarkRead) {
      const cached = readMessagingBootstrapCache(key)
      if (cached) {
        return {
          bootstrap: cached,
          source: "cache",
          rpcVersion: null,
          dualRunMismatches: 0,
          rpcRequestCount: 0,
          durationMs: 0,
          payloadBytes: 0,
          cacheHit: true,
        }
      }
    }

    const rpcRepo = new MessagingRpcBootstrapRepository(client, uid)
    const restRepo = new MessagingRestBootstrapRepository(client, uid)
    const input: MessagingBootstrapInput = {
      cursor,
      limit,
      markMessageNotificationsRead: needsMarkRead,
    }

    const { value: rpcResult, ms } = await measureAsync(() =>
      rpcRepo.loadMessagesBootstrap(input)
    )
    const rpc = rpcResult.bootstrap
    const rpcVersion = rpcResult.rpcVersion
    let rpcRequestCount = rpcVersion === "v1" && needsMarkRead && !cursor ? 2 : 1

    let dualRunMismatches = 0
    const dualRun =
      process.env.NODE_ENV === "development" &&
      (process.env.NEXT_PUBLIC_BACKEND_V2_DUAL_RUN === "1" ||
        process.env.NEXT_PUBLIC_BACKEND_V2_DUAL_RUN === "true")
    if (dualRun && !cursor) {
      try {
        const rest = await restRepo.loadMessagesBootstrap(input)
        const mismatches = compareMessagingBootstraps(rest, rpc)
        dualRunMismatches = mismatches.length
        logMessagingBootstrapMismatches(mismatches)
      } catch (err) {
        console.warn("[backendV2.messages] dual-run REST failed", err)
        dualRunMismatches = -1
      }
    }

    if (!cursor) {
      writeMessagingBootstrapCache(key, uid, rpc, "rpc")
    }

    let payloadBytes = 0
    try {
      payloadBytes = utf8ByteLength(JSON.stringify(rpc))
    } catch {
      payloadBytes = 0
    }

    recordBackendV2Telemetry({
      rpcName:
        rpcVersion === "v2"
          ? BackendV2RpcNames.messaging
          : BackendV2RpcNames.messagingV1,
      success: true,
      executionMs: ms,
      decodeMs: null,
      payloadBytes,
      cacheHit: false,
      cacheMiss: true,
      errorCode: null,
      flagName: "backendV2.messages",
    })

    return {
      bootstrap: rpc,
      source: "rpc",
      rpcVersion,
      dualRunMismatches,
      rpcRequestCount,
      durationMs: ms,
      payloadBytes,
      cacheHit: false,
    }
  })
}

export {
  clearMessagingBootstrapCache,
  invalidateMessagingBootstrap,
  readMessagingBootstrapCache,
} from "./messagingBootstrapCache.ts"
