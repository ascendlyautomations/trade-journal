/**
 * Personal conversation thread bootstrap repository — RPC with controlled legacy fallback.
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import { mapProjectedRows } from "../supabaseProjectedQuery.ts"
import { isConversationParticipant } from "../conversationAccess.ts"
import { fetchDmBlockStatus } from "../conversationBlocks.ts"
import { fetchConversationNotificationsEnabled } from "../conversationMemberPreferences.ts"
import { markConversationMessagesSeen } from "../conversationReadMarking.ts"
import { filterMessagesForUser, sortMessagesByCreatedAt } from "../conversationMessageUtils.ts"
import { queryDmMessages } from "../dmMessageSelect.ts"
import { markNotificationsReadForTarget } from "../notificationReadSync.ts"
import {
  ConversationThreadContractError,
  decodeConversationThreadBootstrapV1,
  decodeConversationThreadMessageV1,
  type ConversationThreadBootstrapV1,
  type ConversationThreadMessageV1,
} from "./conversationThreadContracts.ts"
import {
  conversationThreadCacheKey,
  invalidateConversationThread,
  isConversationThreadCacheSoftStale,
  readConversationThreadCache,
  readConversationThreadPaginationCursor,
  writeConversationThreadCache,
  patchConversationThreadMessages,
} from "./conversationThreadBootstrapCache.ts"
import {
  beginConversationThreadFlight,
  getConversationThreadFlight,
} from "./conversationThreadBootstrapSingleFlight.ts"
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
  isConversationThreadRpcUnavailable,
  isConversationThreadTransientError,
  logConversationThreadRpcUnavailable,
} from "./conversationThreadRpcCompat.ts"
import {
  clearConversationThreadRpcUnavailableCache,
  isConversationThreadRpcCachedUnavailable,
  markConversationThreadRpcUnavailable,
} from "./conversationThreadV1Availability.ts"

export const CONVERSATION_THREAD_MESSAGE_LIMIT = 50

export type ConversationThreadBootstrapInput = {
  conversationId: string
  messageLimit?: number
  cursor?: string | null
  /** Intentional thread open only — never pagination/revalidation. */
  markRead?: boolean
  force?: boolean
  caller?: string
}

export type ConversationThreadLoadResult = {
  bootstrap: ConversationThreadBootstrapV1
  source: "rpc" | "legacy" | "cache"
  rpcRequestCount: number
  durationMs: number
  payloadBytes: number
  cacheHit: boolean
  staleRejected?: boolean
  usedLegacyFallback?: boolean
  pagination?: boolean
}

export class ConversationThreadLoadError extends Error {
  readonly causeError: unknown

  constructor(message: string, causeError?: unknown) {
    super(message)
    this.name = "ConversationThreadLoadError"
    this.causeError = causeError
  }
}

export class ConversationThreadStaleError extends Error {
  constructor() {
    super("conversation_thread_stale")
    this.name = "ConversationThreadStaleError"
  }
}

async function fetchDeletedMessageIds(
  client: SupabaseClient,
  userId: string,
  messageIds: string[]
): Promise<Set<string>> {
  if (messageIds.length === 0) return new Set()
  const { data } = await client
    .from("message_deletions")
    .select("message_id")
    .eq("user_id", userId)
    .in("message_id", messageIds)
  return new Set((data || []).map((row) => String(row.message_id)))
}

function mapLegacyMessages(raw: unknown[]): ConversationThreadMessageV1[] {
  return raw.map((row) => decodeConversationThreadMessageV1(row))
}

async function loadConversationThreadLegacy(
  client: SupabaseClient,
  userId: string,
  input: ConversationThreadBootstrapInput
): Promise<ConversationThreadBootstrapV1> {
  const conversationId = input.conversationId.trim()
  const limit = input.messageLimit ?? CONVERSATION_THREAD_MESSAGE_LIMIT
  const markRead = input.markRead === true
  const cursor = input.cursor?.trim() || null

  if (!(await isConversationParticipant(conversationId, userId))) {
    throw new ConversationThreadLoadError("conversation_access_denied")
  }

  const { data: convo } = await client
    .from("conversations")
    .select("id, is_group, name, avatar_url, is_pinned")
    .eq("id", conversationId)
    .maybeSingle()

  if (!convo) throw new ConversationThreadLoadError("conversation_not_found")

  const notificationsEnabled = await fetchConversationNotificationsEnabled(
    userId,
    conversationId,
    client
  )

  const { data: participantRows } = await client
    .from("conversation_participants")
    .select(`
      user_id,
      profiles (id, username, avatar_url)
    `)
    .eq("conversation_id", conversationId)

  let blockStatus = null
  if (convo.is_group !== true) {
    const block = await fetchDmBlockStatus(conversationId, client)
    if (block.ok) {
      blockStatus = {
        other_user_id: block.status.otherUserId,
        blocked_by_me: block.status.blockedByMe,
        blocked_by_other: block.status.blockedByOther,
      }
    }
  }

  const { data: fetched, error } = await queryDmMessages((select) =>
    (() => {
      let q = client
        .from("messages")
        .select(select)
        .eq("conversation_id", conversationId)

      if (cursor) {
        const parts = cursor.split("|")
        if (parts.length >= 2) {
          const cursorTs = parts[0]
          const cursorId = parts[1]
          q = q.or(
            `created_at.lt.${cursorTs},and(created_at.eq.${cursorTs},id.lt.${cursorId})`
          )
        }
      }

      return q
        .order("created_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(limit + 1)
        .overrideTypes<Record<string, unknown>[], { merge: false }>()
    })()
  )

  if (error) throw new ConversationThreadLoadError(error.message, error)

  const fetchedRows = mapProjectedRows(fetched, (row) => row)
  const page = fetchedRows.slice(0, limit)
  const hasMore = fetchedRows.length > limit
  const deletedIds = await fetchDeletedMessageIds(
    client,
    userId,
    page.map((m) => String(m.id))
  )
  const filtered = sortMessagesByCreatedAt(
    filterMessagesForUser(page, deletedIds)
  )
  const messages = mapLegacyMessages(filtered)

  let nextCursor: string | null = null
  if (messages.length > 0) {
    const oldest = messages[0]
    if (oldest?.created_at && oldest.id) {
      nextCursor = `${oldest.created_at}|${oldest.id}`
    }
  }

  let notificationsMarked = 0
  if (markRead) {
    await markConversationMessagesSeen(userId, conversationId)
    notificationsMarked = await markNotificationsReadForTarget(
      userId,
      { kind: "conversation", conversationId },
      client
    )
  }

  return {
    meta: {
      contract_version: "v1",
      server_time: new Date().toISOString(),
      viewer_id: userId,
    },
    data: {
      conversation: {
        id: String(convo.id),
        is_group: convo.is_group === true,
        name: convo.name ?? null,
        avatar_url: convo.avatar_url ?? null,
        is_pinned: convo.is_pinned === true,
      },
      membership: { is_participant: true },
      participants: (participantRows || []).map((row: any) => ({
        user_id: String(row.user_id),
        profiles: Array.isArray(row.profiles)
          ? row.profiles[0]
          : row.profiles,
      })),
      notifications_enabled: notificationsEnabled,
      block_status: blockStatus,
      messages,
      has_more_messages: hasMore,
      next_message_cursor: hasMore ? nextCursor : null,
      unread_count: markRead ? 0 : 0,
      mark_read: { applied: markRead },
      notifications_marked_read: notificationsMarked,
      page_meta: {
        limit,
        returned: messages.length,
        has_more: hasMore,
      },
    },
  }
}

export async function loadConversationThreadBootstrap(
  client: SupabaseClient,
  userId: string,
  input: ConversationThreadBootstrapInput,
  options?: { loadGeneration?: number; expectedGeneration?: number }
): Promise<ConversationThreadLoadResult> {
  const uid = userId.trim()
  const conversationId = input.conversationId.trim()
  if (!uid || !conversationId) {
    throw new Error("loadConversationThreadBootstrap requires userId and conversationId")
  }

  const isPagination = Boolean(input.cursor?.trim())
  const markRead = input.markRead === true && !isPagination
  const key = conversationThreadCacheKey({ userId: uid, conversationId })
  const flightKey = isPagination ? `${key}|page:${input.cursor}` : key

  if (input.force) invalidateConversationThread(uid, conversationId)

  const canUseCache = !input.force && !markRead && !isPagination

  if (canUseCache) {
    const cached = readConversationThreadCache(key)
    if (cached && !isConversationThreadCacheSoftStale(key)) {
      return {
        bootstrap: cached,
        source: "cache",
        rpcRequestCount: 0,
        durationMs: 0,
        payloadBytes: 0,
        cacheHit: true,
      }
    }
    const existing = getConversationThreadFlight<ConversationThreadLoadResult>(flightKey)
    if (existing) return existing
  } else if (isPagination) {
    const existing = getConversationThreadFlight<ConversationThreadLoadResult>(flightKey)
    if (existing) return existing
  }

  return beginConversationThreadFlight(flightKey, uid, async () => {
    if (canUseCache) {
      const cached = readConversationThreadCache(key)
      if (cached && !isConversationThreadCacheSoftStale(key)) {
        return {
          bootstrap: cached,
          source: "cache",
          rpcRequestCount: 0,
          durationMs: 0,
          payloadBytes: 0,
          cacheHit: true,
        }
      }
    }

    const rpcClient = new BackendV2RpcClient({
      transport: createSupabaseBackendV2Transport(client),
    })

    const runLegacy = async (): Promise<ConversationThreadLoadResult> => {
      const { value: bootstrap, ms } = await measureAsync(() =>
        loadConversationThreadLegacy(client, uid, { ...input, markRead })
      )
      if (!markRead && !isPagination) {
        writeConversationThreadCache(key, uid, conversationId, bootstrap, "legacy")
      } else if (isPagination) {
        const cached = readConversationThreadCache(key)
        if (cached) {
          const merged = [...bootstrap.data.messages, ...cached.data.messages]
          patchConversationThreadMessages(
            key,
            merged,
            bootstrap.data.has_more_messages,
            bootstrap.data.next_message_cursor
          )
          bootstrap.data.messages = merged
        }
      }
      const payloadBytes = utf8ByteLength(JSON.stringify(bootstrap))
      recordBackendV2Telemetry({
        rpcName: "legacy_conversation_thread_chain",
        success: true,
        executionMs: ms,
        decodeMs: null,
        payloadBytes,
        cacheHit: null,
        cacheMiss: true,
        errorCode: null,
        flagName: "backendV2.messageThreads",
      })
      return {
        bootstrap,
        source: "legacy",
        rpcRequestCount: markRead ? 7 : 6,
        durationMs: ms,
        payloadBytes,
        cacheHit: false,
        usedLegacyFallback: true,
        pagination: isPagination,
      }
    }

    if (
      !isBackendV2Enabled("messageThreads") ||
      isConversationThreadRpcCachedUnavailable()
    ) {
      return runLegacy()
    }

    try {
      const { value: bootstrap, ms } = await measureAsync(async () => {
        const raw = await rpcClient.callKnown(
          BackendV2RpcNames.conversationThread,
          decodeConversationThreadBootstrapV1,
          {
            args: {
              p_conversation_id: conversationId,
              p_message_limit: input.messageLimit ?? CONVERSATION_THREAD_MESSAGE_LIMIT,
              p_cursor: input.cursor ?? null,
              p_mark_read: markRead,
            },
            flagName: "backendV2.messageThreads",
            cacheMiss: true,
          }
        )
        if (
          options?.expectedGeneration != null &&
          options.loadGeneration !== options.expectedGeneration
        ) {
          throw new ConversationThreadStaleError()
        }
        return raw
      })

      clearConversationThreadRpcUnavailableCache()

      if (!markRead && !isPagination) {
        writeConversationThreadCache(key, uid, conversationId, bootstrap, "rpc")
      } else if (isPagination) {
        const cached = readConversationThreadCache(key)
        if (cached) {
          const merged = [...bootstrap.data.messages, ...cached.data.messages]
          patchConversationThreadMessages(
            key,
            merged,
            bootstrap.data.has_more_messages,
            bootstrap.data.next_message_cursor
          )
          bootstrap.data.messages = merged
        }
      }

      const payloadBytes = utf8ByteLength(JSON.stringify(bootstrap))
      recordBackendV2Telemetry({
        rpcName: BackendV2RpcNames.conversationThread,
        success: true,
        executionMs: ms,
        decodeMs: null,
        payloadBytes,
        cacheHit: null,
        cacheMiss: true,
        errorCode: null,
        flagName: "backendV2.messageThreads",
      })

      return {
        bootstrap,
        source: "rpc",
        rpcRequestCount: 1,
        durationMs: ms,
        payloadBytes,
        cacheHit: false,
        pagination: isPagination,
      }
    } catch (err) {
      if (err instanceof ConversationThreadStaleError) throw err
      if (err instanceof ConversationThreadContractError) {
        throw new ConversationThreadLoadError(err.message, err)
      }
      if (isConversationThreadTransientError(err)) {
        throw new ConversationThreadLoadError(
          "Conversation thread bootstrap temporarily unavailable",
          err
        )
      }
      if (isConversationThreadRpcUnavailable(err)) {
        logConversationThreadRpcUnavailable(err)
        markConversationThreadRpcUnavailable()
        return runLegacy()
      }
      throw err
    }
  })
}

export function readConversationThreadNextCursor(
  userId: string,
  conversationId: string
): string | null {
  const key = conversationThreadCacheKey({ userId, conversationId })
  return (
    readConversationThreadPaginationCursor(key) ??
    readConversationThreadCache(key)?.data.next_message_cursor ??
    null
  )
}
