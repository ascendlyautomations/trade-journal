import type { NotificationRecord } from "@/lib/notificationsDisplay"
import { demoAvatarUrl } from "./demoAvatars"
import { DEMO_USER_ID } from "./constants"
import {
  DEMO_USER_ALEX,
  DEMO_USER_JORDAN,
  DEMO_USER_MIKE,
  DEMO_USER_SARAH,
} from "./demoFeed"
import { getDemoProfileById } from "./demoProfile"
import { isoDemoDaysAgo } from "./demoTime"

const DEMO_NOTIFICATIONS: NotificationRecord[] = [
  {
    id: "demo-notif-1",
    user_id: DEMO_USER_ID,
    sender_id: DEMO_USER_ALEX,
    type: "like",
    post_id: "demo-post-1",
    trade_id: "dt-24",
    profile_post_id: null,
    achievement_post_id: null,
    reel_id: null,
    comment_id: null,
    content: null,
    read: false,
    created_at: isoDemoDaysAgo(0, 11),
  },
  {
    id: "demo-notif-2",
    user_id: DEMO_USER_ID,
    sender_id: DEMO_USER_SARAH,
    type: "comment",
    post_id: "demo-post-1",
    trade_id: "dt-24",
    profile_post_id: null,
    achievement_post_id: null,
    reel_id: null,
    comment_id: "demo-comment-2",
    content: "What timeframe for the sweep?",
    read: false,
    created_at: isoDemoDaysAgo(0, 12),
  },
  {
    id: "demo-notif-3",
    user_id: DEMO_USER_ID,
    sender_id: DEMO_USER_JORDAN,
    type: "follow",
    post_id: null,
    trade_id: null,
    profile_post_id: null,
    achievement_post_id: null,
    reel_id: null,
    comment_id: null,
    content: null,
    read: false,
    created_at: isoDemoDaysAgo(1, 9),
  },
  {
    id: "demo-notif-4",
    user_id: DEMO_USER_ID,
    sender_id: DEMO_USER_MIKE,
    type: "like",
    post_id: null,
    profile_post_id: null,
    achievement_post_id: null,
    reel_id: "demo-reel-1",
    comment_id: null,
    content: null,
    read: true,
    created_at: isoDemoDaysAgo(1, 16),
  },
  {
    id: "demo-notif-5",
    user_id: DEMO_USER_ID,
    sender_id: DEMO_USER_ALEX,
    type: "room_message",
    post_id: null,
    trade_id: null,
    profile_post_id: null,
    achievement_post_id: null,
    reel_id: null,
    comment_id: null,
    content: "Futures green pre-market. Watching 19000 on NQ for reaction.",
    read: false,
    created_at: isoDemoDaysAgo(0, 8),
  },
  {
    id: "demo-notif-6",
    user_id: DEMO_USER_ID,
    sender_id: DEMO_USER_SARAH,
    type: "room_join",
    post_id: null,
    trade_id: null,
    profile_post_id: null,
    achievement_post_id: null,
    reel_id: null,
    comment_id: null,
    content: null,
    read: true,
    created_at: isoDemoDaysAgo(3, 10),
  },
  {
    id: "demo-notif-7",
    user_id: DEMO_USER_ID,
    sender_id: DEMO_USER_MIKE,
    type: "like",
    post_id: null,
    trade_id: null,
    profile_post_id: null,
    achievement_post_id: "demo-achievement-1",
    reel_id: null,
    comment_id: null,
    content: null,
    read: true,
    created_at: isoDemoDaysAgo(2, 16),
  },
  {
    id: "demo-notif-8",
    user_id: DEMO_USER_ID,
    sender_id: DEMO_USER_ALEX,
    type: "comment",
    post_id: null,
    trade_id: null,
    profile_post_id: null,
    achievement_post_id: null,
    reel_id: "demo-reel-1",
    comment_id: "demo-comment-mention",
    content: "@john_trades great breakdown in Trade Rooms",
    read: false,
    created_at: isoDemoDaysAgo(0, 13),
  },
]

export function fetchDemoNotifications(userId: string): NotificationRecord[] {
  if (userId !== DEMO_USER_ID) return []
  return [...DEMO_NOTIFICATIONS].sort(
    (a, b) =>
      new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  )
}

export function getDemoUnreadNotificationCount(userId: string): number {
  return fetchDemoNotifications(userId).filter((n) => !n.read).length
}

export function getDemoNotificationSenderProfiles(
  senderIds: string[]
): Record<string, { id: string; username: string; name: string; avatar_url: string | null }> {
  const out: Record<
    string,
    { id: string; username: string; name: string; avatar_url: string | null }
  > = {}
  for (const id of senderIds) {
    const profile = getDemoProfileById(id)
    if (profile) {
      out[id] = {
        id: profile.id,
        username: profile.username,
        name: profile.name,
        avatar_url: profile.avatar_url,
      }
    } else {
      out[id] = {
        id,
        username: "trader",
        name: "Trader",
        avatar_url: demoAvatarUrl(id),
      }
    }
  }
  return out
}
