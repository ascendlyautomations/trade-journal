/**
 * Trade Room bootstrap repository — RPC with controlled legacy fallback.
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import { mapProjectedRows } from "@/lib/supabaseProjectedQuery"
import { fetchRoomChannelNotificationPrefs } from "@/lib/roomChannelNotificationPreferences.ts"
import {
  decodeRoomBootstrapV1,
  decodeRoomMessageV1,
  RoomBootstrapContractError,
  type RoomBootstrapV1,
  type RoomSectionV1,
} from "./roomContracts.ts"
import {
  isRoomBootstrapCacheSoftStale,
  readRoomBootstrapCache,
  roomBootstrapCacheKey,
  writeRoomBootstrapCache,
  invalidateRoomBootstrap,
} from "./roomBootstrapCache.ts"
import {
  beginRoomBootstrapFlight,
  getRoomBootstrapFlight,
} from "./roomBootstrapSingleFlight.ts"
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
  isRoomBootstrapRpcUnavailable,
  isRoomBootstrapTransientError,
  logRoomBootstrapRpcUnavailable,
} from "./roomRpcCompat.ts"
import {
  clearRoomBootstrapRpcUnavailableCache,
  isRoomBootstrapRpcCachedUnavailable,
  markRoomBootstrapRpcUnavailable,
} from "./roomV1Availability.ts"
import { ROOM_MESSAGE_SELECT_COMPACT } from "@/lib/roomMessageSelect"

export const ROOM_BOOTSTRAP_MESSAGE_LIMIT = 25

export type RoomBootstrapInput = {
  roomId: string
  sectionId?: string | null
  messageLimit?: number
  /** Intentional first-page room open only — never for pagination/prefetch. */
  markRead?: boolean
  force?: boolean
  caller?: string
}

export type RoomBootstrapLoadResult = {
  bootstrap: RoomBootstrapV1
  source: "rpc" | "legacy" | "cache"
  rpcRequestCount: number
  durationMs: number
  payloadBytes: number
  cacheHit: boolean
  staleRejected?: boolean
  usedLegacyFallback?: boolean
}

export class RoomBootstrapLoadError extends Error {
  readonly causeError: unknown

  constructor(message: string, causeError?: unknown) {
    super(message)
    this.name = "RoomBootstrapLoadError"
    this.causeError = causeError
  }
}

function resolveActiveSection(
  sections: RoomSectionV1[],
  preferredSectionId?: string | null
): { activeSectionId: string | null; activeSectionName: string | null } {
  if (sections.length === 0) {
    return { activeSectionId: null, activeSectionName: null }
  }
  const resolved =
    preferredSectionId &&
    sections.some((s) => s.id === preferredSectionId)
      ? preferredSectionId
      : sections[0]!.id
  const section = sections.find((s) => s.id === resolved)
  return {
    activeSectionId: resolved,
    activeSectionName: section?.name ?? null,
  }
}

function applySectionFilter<T extends { eq: Function; or: Function; is: Function }>(
  q: T,
  roomId: string,
  sections: RoomSectionV1[],
  activeSectionId: string | null
): T {
  let next = q.eq("room_id", roomId) as T
  if (sections.length === 0 || !activeSectionId) return next
  const section = sections.find((s) => s.id === activeSectionId)
  const nameLower = String(section?.name ?? "").trim().toLowerCase()
  if (nameLower === "general") {
    next = next.or(
      `section_id.eq.${activeSectionId},section_id.is.null`
    ) as T
  } else {
    next = next.eq("section_id", activeSectionId) as T
  }
  return next
}

async function loadRoomBootstrapLegacy(
  client: SupabaseClient,
  userId: string,
  input: RoomBootstrapInput
): Promise<RoomBootstrapV1> {
  const roomId = input.roomId
  const limit = Math.max(
    1,
    Math.min(input.messageLimit ?? ROOM_BOOTSTRAP_MESSAGE_LIMIT, 50)
  )
  const serverTime = new Date().toISOString()

  const { data: roomRow, error: roomError } = await client
    .from("rooms")
    .select(
      "id, name, description, slug, image_url, owner_user_id, show_on_profile"
    )
    .eq("id", roomId)
    .maybeSingle()
  if (roomError || !roomRow) throw roomError ?? new Error("room_not_found")

  const { data: memberRow, error: memberError } = await client
    .from("room_members")
    .select("notification_enabled, left_at")
    .eq("room_id", roomId)
    .eq("user_id", userId)
    .maybeSingle()
  if (memberError || !memberRow || memberRow.left_at != null) {
    throw memberError ?? new Error("room_access_denied")
  }

  const { data: sectionRows, error: sectionError } = await client
    .from("room_sections")
    .select("id, room_id, name, position, allow_members_chat")
    .eq("room_id", roomId)
    .order("position", { ascending: true })
  if (sectionError) throw sectionError

  const sections: RoomSectionV1[] = (sectionRows ?? []).map((s) => ({
    id: String(s.id),
    room_id: String(s.room_id),
    name: String(s.name ?? ""),
    position: Number(s.position) || 0,
    allow_members_chat: s.allow_members_chat !== false,
  }))

  const { activeSectionId, activeSectionName } = resolveActiveSection(
    sections,
    input.sectionId
  )

  const channelPrefs = await fetchRoomChannelNotificationPrefs(
    client,
    roomId,
    userId,
    sections
  )

  const isOwner = String(roomRow.owner_user_id) === userId
  let memberStats: RoomBootstrapV1["data"]["member_stats"] = null
  if (isOwner) {
    const [{ count: active }, { count: total }] = await Promise.all([
      client
        .from("room_members")
        .select("*", { count: "exact", head: true })
        .eq("room_id", roomId)
        .is("left_at", null),
      client
        .from("room_members")
        .select("*", { count: "exact", head: true })
        .eq("room_id", roomId),
    ])
    const activeN = active ?? 0
    const totalN = total ?? 0
    memberStats = {
      active_members: activeN,
      total_members: totalN,
      left_members: Math.max(totalN - activeN, 0),
    }
  }

  if (input.markRead) {
    await client.rpc("mark_room_read", { p_room_id: roomId })
  }

  const { data: unreadRows } = await client.rpc("get_room_unread_counts", {
    p_room_ids: [roomId],
  })
  const unreadCount = Number(
    (unreadRows as Array<{ unread_count: number }> | null)?.[0]?.unread_count ??
      0
  )

  let pinnedQ = client
    .from("room_messages")
    .select(ROOM_MESSAGE_SELECT_COMPACT)
    .eq("pinned", true)
    .order("created_at", { ascending: false })
    .limit(100)
  pinnedQ = applySectionFilter(pinnedQ, roomId, sections, activeSectionId)

  let mainQ = client
    .from("room_messages")
    .select(ROOM_MESSAGE_SELECT_COMPACT)
    .eq("pinned", false)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(limit + 1)
  mainQ = applySectionFilter(mainQ, roomId, sections, activeSectionId)

  const [pinnedRes, mainRes] = await Promise.all([
    pinnedQ.overrideTypes<Record<string, unknown>[], { merge: false }>(),
    mainQ.overrideTypes<Record<string, unknown>[], { merge: false }>(),
  ])
  if (pinnedRes.error) throw pinnedRes.error
  if (mainRes.error) throw mainRes.error

  const pinnedRaw = mapProjectedRows(pinnedRes.data, (row) => row).slice().reverse()
  const mainRows = mapProjectedRows(mainRes.data, (row) => row)
  const hasMore = mainRows.length > limit
  const mainRaw = mainRows.slice(0, limit).reverse()
  const oldest = mainRaw[0] as { created_at?: string; id?: string } | undefined
  const nextCursor =
    oldest?.created_at && oldest?.id
      ? `${oldest.created_at}|${oldest.id}`
      : null

  return {
    meta: {
      contract_version: "v1",
      server_time: serverTime,
      viewer_id: userId,
    },
    data: {
      room: {
        id: String(roomRow.id),
        name: roomRow.name ?? null,
        description: roomRow.description ?? null,
        slug: roomRow.slug ?? null,
        image_url: roomRow.image_url ?? null,
        owner_user_id: roomRow.owner_user_id ?? null,
        is_public: true,
        allow_members_chat: true,
        show_on_profile: roomRow.show_on_profile !== false,
        created_at: null,
      },
      membership: {
        notification_enabled: memberRow.notification_enabled !== false,
        is_owner: isOwner,
      },
      sections,
      active_section_id: activeSectionId,
      channel_preferences: channelPrefs,
      member_stats: memberStats,
      unread_count: unreadCount,
      mark_read: { applied: input.markRead === true },
      pinned_messages: pinnedRaw.map(decodeRoomMessageV1),
      messages: mainRaw.map(decodeRoomMessageV1),
      has_more_messages: hasMore,
      next_message_cursor: nextCursor,
    },
  }
}

export async function loadRoomBootstrapForUser(
  client: SupabaseClient,
  userId: string,
  input: RoomBootstrapInput,
  options?: { loadGeneration?: number; expectedGeneration?: number }
): Promise<RoomBootstrapLoadResult> {
  const uid = userId.trim()
  const roomId = input.roomId.trim()
  if (!uid || !roomId) throw new Error("loadRoomBootstrapForUser requires userId and roomId")

  const key = roomBootstrapCacheKey({
    userId: uid,
    roomId,
    sectionId: input.sectionId,
  })

  if (input.force) invalidateRoomBootstrap(uid, roomId)

  const markRead = input.markRead === true
  const canUseCache = !input.force && !markRead

  if (canUseCache) {
    const cached = readRoomBootstrapCache(key)
    if (cached && !isRoomBootstrapCacheSoftStale(key)) {
      return {
        bootstrap: cached,
        source: "cache",
        rpcRequestCount: 0,
        durationMs: 0,
        payloadBytes: 0,
        cacheHit: true,
      }
    }
    const existing = getRoomBootstrapFlight<RoomBootstrapLoadResult>(key)
    if (existing) return existing
  }

  return beginRoomBootstrapFlight(key, uid, async () => {
    if (canUseCache) {
      const cached = readRoomBootstrapCache(key)
      if (cached && !isRoomBootstrapCacheSoftStale(key)) {
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

    const runLegacy = async (): Promise<RoomBootstrapLoadResult> => {
      const { value: bootstrap, ms } = await measureAsync(() =>
        loadRoomBootstrapLegacy(client, uid, input)
      )
      if (!markRead) {
        writeRoomBootstrapCache(key, uid, roomId, bootstrap, "legacy")
      }
      const payloadBytes = utf8ByteLength(JSON.stringify(bootstrap))
      recordBackendV2Telemetry({
        rpcName: "legacy_room_chain",
        success: true,
        executionMs: ms,
        decodeMs: null,
        payloadBytes,
        cacheHit: null,
        cacheMiss: true,
        errorCode: null,
        flagName: "backendV2.rooms",
      })
      return {
        bootstrap,
        source: "legacy",
        rpcRequestCount: markRead ? 6 : 5,
        durationMs: ms,
        payloadBytes,
        cacheHit: false,
        usedLegacyFallback: true,
      }
    }

    if (
      !isBackendV2Enabled("rooms") ||
      isRoomBootstrapRpcCachedUnavailable()
    ) {
      return runLegacy()
    }

    try {
      const { value: bootstrap, ms } = await measureAsync(async () => {
        const raw = await rpcClient.callKnown(
          BackendV2RpcNames.room,
          decodeRoomBootstrapV1,
          {
            args: {
              p_room_id: roomId,
              p_section_id: input.sectionId ?? null,
              p_message_limit: input.messageLimit ?? ROOM_BOOTSTRAP_MESSAGE_LIMIT,
              p_mark_read: markRead,
            },
            flagName: "backendV2.rooms",
            cacheMiss: true,
          }
        )
        if (
          options?.expectedGeneration != null &&
          options.loadGeneration !== options.expectedGeneration
        ) {
          throw new RoomBootstrapStaleError()
        }
        return raw
      })

      clearRoomBootstrapRpcUnavailableCache()
      if (!markRead) {
        writeRoomBootstrapCache(key, uid, roomId, bootstrap, "rpc")
      }

      const payloadBytes = utf8ByteLength(JSON.stringify(bootstrap))
      recordBackendV2Telemetry({
        rpcName: BackendV2RpcNames.room,
        success: true,
        executionMs: ms,
        decodeMs: null,
        payloadBytes,
        cacheHit: null,
        cacheMiss: true,
        errorCode: null,
        flagName: "backendV2.rooms",
      })

      return {
        bootstrap,
        source: "rpc",
        rpcRequestCount: 1,
        durationMs: ms,
        payloadBytes,
        cacheHit: false,
      }
    } catch (err) {
      if (err instanceof RoomBootstrapStaleError) {
        throw err
      }
      if (err instanceof RoomBootstrapContractError) {
        throw new RoomBootstrapLoadError(err.message, err)
      }
      if (isRoomBootstrapTransientError(err)) {
        throw new RoomBootstrapLoadError(
          "Trade Room bootstrap temporarily unavailable",
          err
        )
      }
      if (isRoomBootstrapRpcUnavailable(err)) {
        logRoomBootstrapRpcUnavailable(err)
        markRoomBootstrapRpcUnavailable()
        return runLegacy()
      }
      throw err
    }
  })
}

export class RoomBootstrapStaleError extends Error {
  constructor() {
    super("room_bootstrap_stale")
    this.name = "RoomBootstrapStaleError"
  }
}

export { clearRoomBootstrapCache, invalidateRoomBootstrap } from "./roomBootstrapCache.ts"
