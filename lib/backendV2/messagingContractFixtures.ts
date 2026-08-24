/**
 * Phase C: Messaging bootstrap contract fixtures.
 */

import type { MessagesBootstrapV1 } from "./contracts.ts"

const VIEWER = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
const PEER = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
const TS = "2026-08-20T15:00:00.000Z"

const meta = {
  contract_version: "v1" as const,
  server_time: TS,
  viewer_id: VIEWER,
}

function participant(
  userId: string,
  username: string,
  avatar: string | null = null
) {
  return {
    user_id: userId,
    username,
    display_name: username,
    avatar_url: avatar,
  }
}

function base(overrides: Partial<MessagesBootstrapV1["data"]>): MessagesBootstrapV1 {
  return {
    meta,
    data: {
      conversations: [],
      peers: {},
      dm_unread_total: 0,
      muted_ids: [],
      next_cursor: null,
      page_meta: { limit: 40, returned: 0, has_more: false },
      ...overrides,
    },
  }
}

function personalConv(
  id: string,
  opts?: {
    unread?: number
    muted?: boolean
    lastMessage?: string | null
    lastAt?: string | null
  }
) {
  const unread = opts?.muted ? 0 : (opts?.unread ?? 0)
  return {
    id,
    is_group: false,
    is_pinned: false,
    name: null,
    avatar_url: null,
    last_message: opts?.lastMessage ?? "Hey",
    last_message_at: opts?.lastAt ?? TS,
    unread_count: unread,
    muted: opts?.muted ?? false,
    participants: [participant(VIEWER, "viewer"), participant(PEER, "peer_a")],
  }
}

export const messagingContractFixtures = {
  emptyInbox: base({}),

  singlePersonal: base({
    conversations: [personalConv("11111111-1111-1111-1111-111111111111")],
    peers: {
      [PEER]: {
        id: PEER,
        username: "peer_a",
        display_name: "peer_a",
        avatar_url: null,
      },
    },
    dm_unread_total: 1,
    page_meta: { limit: 40, returned: 1, has_more: false },
  }),

  groupConversation: base({
    conversations: [
      {
        id: "22222222-2222-2222-2222-222222222222",
        is_group: true,
        is_pinned: false,
        name: "Desk Chat",
        avatar_url: "https://cdn.example/group.jpg",
        last_message: "Welcome",
        last_message_at: TS,
        unread_count: 2,
        muted: false,
        participants: [
          participant(VIEWER, "viewer"),
          participant(PEER, "peer_a"),
          participant("cccccccc-cccc-cccc-cccc-cccccccccccc", "peer_b"),
        ],
      },
    ],
    dm_unread_total: 2,
    page_meta: { limit: 40, returned: 1, has_more: false },
  }),

  mutedConversation: base({
    conversations: [
      personalConv("11111111-1111-1111-1111-111111111111", {
        muted: true,
        unread: 5,
      }),
    ],
    muted_ids: ["11111111-1111-1111-1111-111111111111"],
    dm_unread_total: 0,
    page_meta: { limit: 40, returned: 1, has_more: false },
  }),

  paginationBoundary: (() => {
    const conversations = Array.from({ length: 40 }, (_, i) =>
      personalConv(
        `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
        { lastAt: `2026-08-20T10:${String(i).padStart(2, "0")}:00.000Z` }
      )
    )
    const last = conversations[conversations.length - 1]
    return base({
      conversations,
      dm_unread_total: 0,
      page_meta: { limit: 40, returned: 40, has_more: true },
      next_cursor: `${last.last_message_at}|${last.id}`,
    })
  })(),

  equalTimestampBoundary: base({
    conversations: [
      personalConv("11111111-1111-1111-1111-111111111111", {
        lastAt: "2026-08-20T11:00:00.000Z",
      }),
      personalConv("22222222-2222-2222-2222-222222222222", {
        lastAt: "2026-08-20T11:00:00.000Z",
      }),
    ],
    page_meta: { limit: 40, returned: 2, has_more: false },
  }),

  inboxOpenMarkRead: base({
    conversations: [personalConv("11111111-1111-1111-1111-111111111111")],
    message_notifications_marked_read: 3,
    page_meta: { limit: 40, returned: 1, has_more: false },
  }),

  noMessagesYet: base({
    conversations: [
      {
        ...personalConv("11111111-1111-1111-1111-111111111111"),
        last_message: null,
        last_message_at: null,
      },
    ],
    page_meta: { limit: 40, returned: 1, has_more: false },
  }),
}
