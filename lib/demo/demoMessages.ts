import { demoAvatarUrl } from "./demoAvatars"
import { DEMO_USER_ID } from "./constants"
import {
  DEMO_USER_ALEX,
  DEMO_USER_JORDAN,
  DEMO_USER_SARAH,
} from "./demoFeed"
import { getDemoProfileById, getDemoProfileList } from "./demoProfile"
import { isoDemoDaysAgo } from "./demoTime"
import { normalizeProfileUsername } from "@/lib/profileUsername"

export const DEMO_CONVERSATION_ALEX = "demo-convo-alex"
export const DEMO_CONVERSATION_JORDAN = "demo-convo-jordan"
export const DEMO_CONVERSATION_GROUP = "demo-convo-group"

type DemoMessageRow = {
  id: string
  conversation_id: string
  sender_id: string
  content: string
  created_at: string
  seen_by: string[]
  message_type?: string | null
  trade_id?: string | null
  parent_message_id?: string | null
  profiles?: { username: string; avatar_url: string | null }
}

const DEMO_MESSAGES: DemoMessageRow[] = [
  {
    id: "demo-msg-1",
    conversation_id: DEMO_CONVERSATION_ALEX,
    sender_id: DEMO_USER_ALEX,
    content: "Hey Maya, loved your NQ opening drive breakdown. What timeframe do you use for the sweep?",
    created_at: isoDemoDaysAgo(0, 9),
    seen_by: [DEMO_USER_ID],
    profiles: {
      username: "alex_futures",
      avatar_url: demoAvatarUrl(DEMO_USER_ALEX),
    },
  },
  {
    id: "demo-msg-2",
    conversation_id: DEMO_CONVERSATION_ALEX,
    sender_id: DEMO_USER_ID,
    content: "Thanks! I watch the 1m for entry but mark levels on 5m/15m. The sweep was on the overnight low from the 15m chart.",
    created_at: isoDemoDaysAgo(0, 9),
    seen_by: [DEMO_USER_ID, DEMO_USER_ALEX],
    profiles: {
      username: "john_trades",
      avatar_url: demoAvatarUrl(DEMO_USER_ID),
    },
  },
  {
    id: "demo-msg-3",
    conversation_id: DEMO_CONVERSATION_ALEX,
    sender_id: DEMO_USER_ALEX,
    content: "Makes sense. I'll try that tomorrow. Appreciate the detail.",
    created_at: isoDemoDaysAgo(0, 10),
    seen_by: [DEMO_USER_ID],
    profiles: {
      username: "alex_futures",
      avatar_url: demoAvatarUrl(DEMO_USER_ALEX),
    },
  },
  {
    id: "demo-msg-4",
    conversation_id: DEMO_CONVERSATION_JORDAN,
    sender_id: DEMO_USER_JORDAN,
    content: "Rough session today. Rushed my entry before confirmation. Your journal template helped me spot the mistake though.",
    created_at: isoDemoDaysAgo(1, 14),
    seen_by: [DEMO_USER_ID],
    profiles: {
      username: "jordan_scalps",
      avatar_url: demoAvatarUrl(DEMO_USER_JORDAN),
    },
  },
  {
    id: "demo-msg-5",
    conversation_id: DEMO_CONVERSATION_JORDAN,
    sender_id: DEMO_USER_ID,
    content: "Happens to everyone. Write down the trigger you skipped. That's the lesson for next time.",
    created_at: isoDemoDaysAgo(1, 15),
    seen_by: [DEMO_USER_ID, DEMO_USER_JORDAN],
    profiles: {
      username: "john_trades",
      avatar_url: demoAvatarUrl(DEMO_USER_ID),
    },
  },
  {
    id: "demo-msg-6",
    conversation_id: DEMO_CONVERSATION_GROUP,
    sender_id: DEMO_USER_SARAH,
    content: "Morning desk is live. Who's trading NQ today?",
    created_at: isoDemoDaysAgo(0, 8),
    seen_by: [DEMO_USER_ID],
    profiles: {
      username: "sarah_indices",
      avatar_url: demoAvatarUrl(DEMO_USER_SARAH),
    },
  },
  {
    id: "demo-msg-7",
    conversation_id: DEMO_CONVERSATION_GROUP,
    sender_id: DEMO_USER_ID,
    content: "In the room now. Watching for opening drive setup.",
    created_at: isoDemoDaysAgo(0, 8),
    seen_by: [DEMO_USER_ID],
    profiles: {
      username: "john_trades",
      avatar_url: demoAvatarUrl(DEMO_USER_ID),
    },
  },
]

type DemoConversationMeta = {
  id: string
  is_group: boolean
  is_pinned: boolean
  name: string | null
  avatar_url: string | null
  last_message: string
  last_message_at: string
  otherUserId: string | null
  username: string
  displayName: string
  participantIds: string[]
}

const DEMO_CONVERSATIONS: DemoConversationMeta[] = [
  {
    id: DEMO_CONVERSATION_ALEX,
    is_group: false,
    is_pinned: true,
    name: null,
    avatar_url: demoAvatarUrl(DEMO_USER_ALEX),
    last_message: DEMO_MESSAGES[2].content,
    last_message_at: DEMO_MESSAGES[2].created_at,
    otherUserId: DEMO_USER_ALEX,
    username: "alex_futures",
    displayName: "alex_futures",
    participantIds: [DEMO_USER_ID, DEMO_USER_ALEX],
  },
  {
    id: DEMO_CONVERSATION_JORDAN,
    is_group: false,
    is_pinned: false,
    name: null,
    avatar_url: demoAvatarUrl(DEMO_USER_JORDAN),
    last_message: DEMO_MESSAGES[4].content,
    last_message_at: DEMO_MESSAGES[4].created_at,
    otherUserId: DEMO_USER_JORDAN,
    username: "jordan_scalps",
    displayName: "jordan_scalps",
    participantIds: [DEMO_USER_ID, DEMO_USER_JORDAN],
  },
  {
    id: DEMO_CONVERSATION_GROUP,
    is_group: true,
    is_pinned: false,
    name: "Morning Desk Crew",
    avatar_url: null,
    last_message: DEMO_MESSAGES[6].content,
    last_message_at: DEMO_MESSAGES[6].created_at,
    otherUserId: null,
    username: "Morning Desk Crew",
    displayName: "Morning Desk Crew",
    participantIds: [DEMO_USER_ID, DEMO_USER_SARAH, DEMO_USER_ALEX],
  },
]

export function isDemoConversationId(id: string): boolean {
  return DEMO_CONVERSATIONS.some((c) => c.id === id)
}

export function fetchDemoConversations(userId: string) {
  if (userId !== DEMO_USER_ID) return []

  return DEMO_CONVERSATIONS.map((meta) => {
    const unreadCount = DEMO_MESSAGES.filter(
      (m) =>
        m.conversation_id === meta.id &&
        m.sender_id !== userId &&
        !m.seen_by.includes(userId)
    ).length

    const participants = meta.participantIds.map((pid) => {
      const profile = getDemoProfileById(pid)
      return {
        conversation_id: meta.id,
        user_id: pid,
        profiles: profile
          ? {
              id: profile.id,
              username: profile.username,
              avatar_url: profile.avatar_url,
              name: profile.name,
            }
          : null,
      }
    })

    return {
      id: meta.id,
      is_group: meta.is_group,
      is_pinned: meta.is_pinned,
      name: meta.name,
      displayName: meta.displayName,
      username: meta.username,
      otherUserId: meta.otherUserId,
      profileUserId: meta.otherUserId,
      avatar_url: meta.avatar_url,
      participants,
      lastMessage: meta.last_message,
      last_message_at: meta.last_message_at,
      unreadCount,
    }
  }).sort(
    (a, b) =>
      new Date(b.last_message_at).getTime() -
      new Date(a.last_message_at).getTime()
  )
}

export function fetchDemoConversationMessages(
  conversationId: string,
  userId: string
): DemoMessageRow[] {
  if (!isDemoConversationParticipant(conversationId, userId)) return []
  return DEMO_MESSAGES.filter((m) => m.conversation_id === conversationId).sort(
    (a, b) =>
      new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  )
}

export function isDemoConversationParticipant(
  conversationId: string,
  userId: string
): boolean {
  const meta = DEMO_CONVERSATIONS.find((c) => c.id === conversationId)
  return meta?.participantIds.includes(userId) ?? false
}

export function resolveDemoConversationIdFromSegment(
  segment: string,
  userId: string
): string | null {
  if (userId !== DEMO_USER_ID) return null
  const trimmed = segment.trim()
  if (isDemoConversationId(trimmed)) return trimmed

  const normalized = normalizeProfileUsername(trimmed).toLowerCase()
  const match = DEMO_CONVERSATIONS.find(
    (c) => !c.is_group && c.username.toLowerCase() === normalized
  )
  return match?.id ?? null
}

export function fetchDemoConversationDetails(
  userId: string,
  conversationId: string
) {
  const meta = DEMO_CONVERSATIONS.find((c) => c.id === conversationId)
  if (!meta || !isDemoConversationParticipant(conversationId, userId)) {
    return null
  }

  const participants = meta.participantIds.map((pid) => {
    const profile = getDemoProfileById(pid)
    return {
      user_id: pid,
      profiles: profile
        ? {
            id: profile.id,
            username: profile.username,
            avatar_url: profile.avatar_url,
            name: profile.name,
          }
        : null,
    }
  })

  const otherUser = meta.is_group
    ? null
    : getDemoProfileById(meta.otherUserId ?? "")

  return {
    conversation: {
      id: meta.id,
      is_group: meta.is_group,
      name: meta.name,
      avatar_url: meta.avatar_url,
    },
    participants,
    otherUser: otherUser
      ? {
          id: otherUser.id,
          username: otherUser.username,
          avatar_url: otherUser.avatar_url,
          name: otherUser.name,
        }
      : null,
  }
}

export function fetchDemoDmSearchUsers(query: string, excludeUserId: string) {
  const q = query.trim().toLowerCase()
  if (!q) return []
  return getDemoProfileList()
    .filter((p) => p.id !== excludeUserId)
    .filter(
      (p) =>
        p.username.toLowerCase().includes(q) ||
        p.name.toLowerCase().includes(q)
    )
    .slice(0, 10)
    .map((p) => ({
      id: p.id,
      username: p.username,
      name: p.name,
      avatar_url: p.avatar_url,
    }))
}

export function getDemoUnreadMessageCount(userId: string): number {
  if (userId !== DEMO_USER_ID) return 0
  return DEMO_MESSAGES.filter(
    (m) => m.sender_id !== userId && !m.seen_by.includes(userId)
  ).length
}

export function getDemoUnreadMessageRows(
  userId: string,
  conversationIds: string[]
): Array<{
  conversation_id: string
  seen_by: unknown
  sender_id: string | null
}> {
  if (userId !== DEMO_USER_ID) return []
  const idSet = new Set(conversationIds)
  return DEMO_MESSAGES.filter(
    (m) =>
      idSet.has(m.conversation_id) &&
      m.sender_id !== userId &&
      !m.seen_by.includes(userId)
  ).map((m) => ({
    conversation_id: m.conversation_id,
    seen_by: m.seen_by,
    sender_id: m.sender_id,
  }))
}

export function getDemoUnreadCountForConversation(
  userId: string,
  conversationId: string
): number {
  if (userId !== DEMO_USER_ID) return 0
  return DEMO_MESSAGES.filter(
    (m) =>
      m.conversation_id === conversationId &&
      m.sender_id !== userId &&
      !m.seen_by.includes(userId)
  ).length
}

export function getDemoConversationUsername(conversationId: string): string | null {
  const meta = DEMO_CONVERSATIONS.find((c) => c.id === conversationId)
  if (!meta) return null
  return meta.is_group ? meta.name : meta.username
}
