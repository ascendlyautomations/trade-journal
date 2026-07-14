import { demoAvatarUrl, demoRoomImageUrl } from "./demoAvatars"
import { DEMO_USER_ID } from "./constants"
import {
  DEMO_USER_ALEX,
  DEMO_USER_JORDAN,
  DEMO_USER_SARAH,
} from "./demoFeed"
import { DEMO_MAYA_ROOM, getDemoProfileById } from "./demoProfile"
import { DEMO_TRADE_ROOMS } from "./fixtures"
import { isoDemoDaysAgo } from "./demoTime"

export type DemoRoom = {
  id: string
  name?: string | null
  description?: string | null
  slug?: string | null
  image_url?: string | null
  avatar_url?: string | null
  owner_user_id?: string | null
  show_on_profile?: boolean | null
}

export type DemoRoomMessage = {
  id: string
  room_id: string
  user_id: string
  content: string
  created_at: string
  pinned?: boolean | null
  section_id?: string | null
  parent_message_id?: string | null
  type?: string | null
  trade_id?: string | null
  image_url?: string | null
  seen_by?: string[]
  profiles?: { username?: string | null; avatar_url?: string | null } | null
  trades?: {
    id?: string
    ticker?: string | null
    image_url?: string | null
    pnl?: number | string | null
    rr?: number | string | null
  } | null
  room_message_reactions?: Array<{
    id: string
    emoji: string
    user_id: string
  }> | null
}

const DEMO_ROOMS: DemoRoom[] = [
  {
    ...DEMO_MAYA_ROOM,
    avatar_url: DEMO_MAYA_ROOM.image_url,
  },
  {
    id: "room-1",
    name: DEMO_TRADE_ROOMS[0].name,
    description: DEMO_TRADE_ROOMS[0].preview,
    slug: "nq-morning-traders",
    image_url: demoRoomImageUrl("room-1"),
    owner_user_id: DEMO_USER_JORDAN,
    show_on_profile: true,
  },
  {
    id: "room-3",
    name: DEMO_TRADE_ROOMS[2].name,
    description: DEMO_TRADE_ROOMS[2].preview,
    slug: "trade-review-lounge",
    image_url: demoRoomImageUrl("room-3"),
    owner_user_id: DEMO_USER_SARAH,
    show_on_profile: true,
  },
]

const DEMO_SECTIONS: Record<
  string,
  Array<{ id: string; name: string | null }>
> = {
  "room-1": [
    { id: "demo-section-general", name: "General" },
    { id: "demo-section-setups", name: "Setups" },
    { id: "demo-section-recap", name: "Recap" },
  ],
  "room-3": [{ id: "demo-section-general-3", name: "General" }],
  [DEMO_MAYA_ROOM.id]: [{ id: "demo-section-maya", name: "General" }],
}

const PROFILE = (userId: string, username: string) => ({
  username,
  avatar_url: demoAvatarUrl(userId),
})

const DEMO_ROOM_MESSAGES: DemoRoomMessage[] = [
  {
    id: "demo-rm-pinned-1",
    room_id: "room-1",
    user_id: DEMO_USER_ID,
    content: "Pinned: Today's NQ long, sweep + BOS entry. Full notes on the trade card.",
    created_at: isoDemoDaysAgo(0, 10),
    pinned: true,
    section_id: "demo-section-general",
    type: "trade",
    trade_id: "dt-24",
    profiles: PROFILE(DEMO_USER_ID, "john_trades"),
    trades: {
      id: "dt-24",
      ticker: "NQ",
      pnl: 1050,
      rr: 2.7,
      image_url: null,
    },
  },
  {
    id: "demo-rm-1",
    room_id: "room-1",
    user_id: DEMO_USER_ALEX,
    content: "Futures green pre-market. Watching 19000 on NQ for reaction.",
    created_at: isoDemoDaysAgo(0, 8),
    section_id: "demo-section-general",
    profiles: PROFILE(DEMO_USER_ALEX, "alex_futures"),
    room_message_reactions: [
      { id: "demo-react-1", emoji: "👀", user_id: DEMO_USER_JORDAN },
      { id: "demo-react-2", emoji: "🔥", user_id: DEMO_USER_ID },
    ],
  },
  {
    id: "demo-rm-2",
    room_id: "room-1",
    user_id: DEMO_USER_JORDAN,
    content: "Same. If we sweep overnight low I'll look for reversal long.",
    created_at: isoDemoDaysAgo(0, 8),
    section_id: "demo-section-general",
    profiles: PROFILE(DEMO_USER_JORDAN, "jordan_scalps"),
  },
  {
    id: "demo-rm-3",
    room_id: "room-1",
    user_id: DEMO_USER_ID,
    content: "Liquidity taken. Waiting for 1m BOS before entry.",
    created_at: isoDemoDaysAgo(0, 9),
    section_id: "demo-section-setups",
    profiles: PROFILE(DEMO_USER_ID, "john_trades"),
    room_message_reactions: [
      { id: "demo-react-3", emoji: "✅", user_id: DEMO_USER_SARAH },
    ],
  },
  {
    id: "demo-rm-4",
    room_id: "room-3",
    user_id: DEMO_USER_SARAH,
    content: "Post your A+ setups here for same-day feedback. One chart per message please.",
    created_at: isoDemoDaysAgo(1, 12),
    pinned: true,
    section_id: "demo-section-general-3",
    profiles: PROFILE(DEMO_USER_SARAH, "sarah_indices"),
  },
  {
    id: "demo-rm-5",
    room_id: DEMO_MAYA_ROOM.id,
    user_id: DEMO_USER_ID,
    content: "Morning desk is open. Live commentary during US open.",
    created_at: isoDemoDaysAgo(0, 7),
    section_id: "demo-section-maya",
    profiles: PROFILE(DEMO_USER_ID, "john_trades"),
  },
]

const DEMO_MEMBER_ROOM_IDS = [DEMO_MAYA_ROOM.id, "room-1", "room-3"]

export function fetchDemoMemberRooms(userId: string): DemoRoom[] {
  if (userId !== DEMO_USER_ID) return []
  return DEMO_ROOMS.filter((r) => DEMO_MEMBER_ROOM_IDS.includes(r.id))
}

export function fetchDemoRoomSections(roomId: string) {
  return DEMO_SECTIONS[roomId] ?? []
}

export function fetchDemoRoomMessages(
  roomId: string,
  activeSectionId: string | null
): { pinned: DemoRoomMessage[]; main: DemoRoomMessage[] } {
  let rows = DEMO_ROOM_MESSAGES.filter((m) => m.room_id === roomId)

  if (activeSectionId) {
    const sections = DEMO_SECTIONS[roomId] ?? []
    const sec = sections.find((s) => s.id === activeSectionId)
    const nameLower = String(sec?.name ?? "").trim().toLowerCase()
    if (nameLower === "general") {
      rows = rows.filter(
        (m) =>
          m.section_id === activeSectionId || m.section_id == null
      )
    } else {
      rows = rows.filter((m) => m.section_id === activeSectionId)
    }
  }

  const pinned = rows
    .filter((m) => m.pinned === true)
    .sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
  const main = rows
    .filter((m) => m.pinned !== true)
    .sort(
      (a, b) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    )

  return { pinned, main }
}

export function fetchDemoRoomOwnerUserId(roomId: string): string | null {
  return DEMO_ROOMS.find((r) => r.id === roomId)?.owner_user_id ?? null
}

export function getDemoRoomMemberStats(_roomId: string) {
  return { active: 12, left: 3 }
}

export function isDemoRoomId(roomId: string): boolean {
  return DEMO_ROOMS.some((r) => r.id === roomId)
}

export function resolveDemoRoomFromParam(param: string): DemoRoom | null {
  const decoded = decodeURIComponent(param.trim())
  return (
    DEMO_ROOMS.find(
      (r) => r.id === decoded || r.slug === decoded || r.slug === param
    ) ?? null
  )
}

export function getDemoRoomUnreadByRoomIds(
  roomIds: string[]
): Record<string, boolean> {
  const unread: Record<string, boolean> = {}
  for (const roomId of roomIds) {
    unread[roomId] = roomId === "room-1"
  }
  return unread
}

export function getDemoActivePresence(roomId: string) {
  if (!DEMO_MEMBER_ROOM_IDS.includes(roomId)) return []
  return [DEMO_USER_ALEX, DEMO_USER_JORDAN, DEMO_USER_SARAH].map((userId) => {
    const profile = getDemoProfileById(userId)
    return {
      user_id: userId,
      profiles: profile
        ? {
            id: profile.id,
            username: profile.username,
            avatar_url: profile.avatar_url,
          }
        : null,
    }
  })
}

export function getDemoChannelNotificationPrefs(
  sections: Array<{ id: string }>
): Record<string, boolean> {
  const prefs: Record<string, boolean> = {}
  for (const section of sections) {
    prefs[section.id] = true
  }
  return prefs
}

export function getDemoPopularTradeRooms() {
  return DEMO_ROOMS.map((room) => ({
    id: room.id,
    name: room.name ?? "Trade Room",
    description: room.description ?? null,
    slug: room.slug ?? null,
    memberCount:
      room.id === "room-1" ? 48 : room.id === "room-3" ? 32 : 15,
    imageUrl: room.image_url ?? null,
    avatarUrl: room.avatar_url ?? null,
  }))
}

export function searchDemoPopularTradeRooms(query: string) {
  const trimmed = query.trim().toLowerCase()
  if (!trimmed) return []
  return getDemoPopularTradeRooms().filter(
    (room) =>
      room.name.toLowerCase().includes(trimmed) ||
      (room.slug?.toLowerCase().includes(trimmed) ?? false)
  )
}
