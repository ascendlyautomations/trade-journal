"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"
import EmptyState from "../components/ui/EmptyState"
import Modal from "../components/ui/Modal"
import { clearAllNotifications, dismissNotifications } from "@/lib/followNotifications"
import { formatEST } from "@/lib/formatEST"
import {
  buildNotificationListItems,
  commentPreview,
  formatFollowMessage,
  formatLikeGroupMessage,
  formatRoomJoinMessage,
  getNotificationHref,
  getNotificationTimeSection,
  groupItemsByTimeSection,
  itemCreatedAt,
  itemIsUnread,
  senderDisplayName,
  type NotificationListItem,
  type NotificationRecord,
  type SenderProfile,
  type TimeSection,
} from "@/lib/notificationsDisplay"

const NOTIFICATIONS_TABLE = "notifications"

const NOTIFICATION_SELECT =
  "id, user_id, sender_id, type, post_id, trade_id, content, read, created_at"

const ENGAGEMENT_TYPES = ["like", "comment", "room_join", "message", "follow"] as const

type SupabaseErrorShape = {
  code?: string
  message?: string
  details?: string
  hint?: string
}

function logNotificationsQueryError(
  action: "fetch" | "mark read" | "mark all read" | "clear all" | "dismiss",
  error: SupabaseErrorShape | null,
  meta: { userId: string | null; columns?: string }
) {
  console.error(`[notifications] ${action} failed`, {
    table: NOTIFICATIONS_TABLE,
    columns: meta.columns ?? NOTIFICATION_SELECT,
    userId: meta.userId,
    error,
    code: error?.code,
    message: error?.message,
    details: error?.details,
    hint: error?.hint,
  })
}

const SECTION_LABELS: Record<TimeSection, string> = {
  today: "Today",
  yesterday: "Yesterday",
  earlier: "Earlier",
}

function timeAgo(ts: string): string {
  const t = new Date(ts).getTime()
  if (!Number.isFinite(t)) return ""
  const s = Math.max(0, Math.floor((Date.now() - t) / 1000))
  if (s < 60) return "just now"
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  if (getNotificationTimeSection(ts) === "earlier") {
    return formatEST(ts)
  }
  return `${Math.floor(s / 86400)}d ago`
}

function NotificationCard({
  unread,
  title,
  body,
  timestamp,
  avatarUrl,
  onClick,
  onDismiss,
  dismissing,
}: {
  unread: boolean
  title: string
  body?: string | null
  timestamp: string
  avatarUrl?: string | null
  onClick: () => void
  onDismiss: () => void
  dismissing?: boolean
}) {
  return (
    <div
      className={`rounded-xl border p-3 transition ${
        unread
          ? "border-blue-400/40 bg-white/10 ring-1 ring-blue-400/30"
          : "border-white/10 bg-white/5"
      }`}
    >
      <div className="flex items-start gap-2 sm:gap-3">
        {avatarUrl != null ? (
          <div className="relative shrink-0">
            <img
              src={avatarUrl || "/default-avatar.png"}
              alt=""
              className="h-9 w-9 rounded-full object-cover ring-2 ring-white/10"
              onError={(e) => {
                e.currentTarget.src = "/default-avatar.png"
              }}
            />
            {unread ? (
              <span
                className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full border-2 border-[#0f172a] bg-blue-400"
                aria-hidden
              />
            ) : null}
          </div>
        ) : unread ? (
          <span
            className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-blue-400"
            aria-hidden
          />
        ) : (
          <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-transparent" />
        )}
        <div
          role="button"
          tabIndex={0}
          onClick={onClick}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault()
              onClick()
            }
          }}
          className="min-w-0 flex-1 cursor-pointer space-y-1 rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-blue-400/50"
        >
          <p
            className={`text-sm ${unread ? "font-semibold text-white" : "text-gray-200"}`}
          >
            {title}
          </p>
          {body ? <p className="text-xs text-gray-400">{body}</p> : null}
          <p className="text-[11px] uppercase tracking-wide text-gray-500">
            {timeAgo(timestamp)}
          </p>
        </div>
        <button
          type="button"
          disabled={dismissing}
          onClick={(e) => {
            e.stopPropagation()
            onDismiss()
          }}
          className="shrink-0 rounded-md p-1.5 text-gray-400 transition hover:bg-white/10 hover:text-white disabled:opacity-40"
          aria-label="Dismiss notification"
        >
          ✕
        </button>
      </div>
    </div>
  )
}

export default function NotificationsPage() {
  const router = useRouter()
  const [userId, setUserId] = useState<string | null>(null)
  const [ownerUsername, setOwnerUsername] = useState<string | null>(null)
  const [notifications, setNotifications] = useState<NotificationRecord[]>([])
  const [sendersById, setSendersById] = useState<Record<string, SenderProfile>>(
    {}
  )
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [showClearConfirm, setShowClearConfirm] = useState(false)
  const [clearing, setClearing] = useState(false)
  const [dismissingIds, setDismissingIds] = useState<Set<string>>(new Set())

  useEffect(() => {
    let cancelled = false

    async function initUser() {
      const { data, error } = await supabase.auth.getUser()
      if (cancelled) return
      if (error || !data?.user) {
        router.push("/login")
        return
      }
      setUserId(data.user.id)

      const { data: ownProfile } = await supabase
        .from("profiles")
        .select("username")
        .eq("id", data.user.id)
        .maybeSingle()

      if (!cancelled) {
        setOwnerUsername(ownProfile?.username ?? null)
      }
    }

    void initUser()
    return () => {
      cancelled = true
    }
  }, [router])

  const fetchNotifications = useCallback(async () => {
    if (!userId) return
    setLoading(true)
    setLoadError(null)

    const { data, error } = await supabase
      .from("notifications")
      .select(NOTIFICATION_SELECT)
      .eq("user_id", userId)
      .in("type", [...ENGAGEMENT_TYPES])
      .order("created_at", { ascending: false })
      .limit(200)

    if (error) {
      logNotificationsQueryError("fetch", error, { userId })
      setNotifications([])
      setLoadError("Could not load notifications right now.")
      setLoading(false)
      return
    }

    const rows = (data || []) as NotificationRecord[]
    setNotifications(rows)

    const senderIds = Array.from(
      new Set(
        rows
          .map((row) => row.sender_id)
          .filter((id): id is string => typeof id === "string" && id.length > 0)
      )
    )

    if (senderIds.length > 0) {
      const { data: profiles } = await supabase
        .from("profiles")
        .select("id, username, name, avatar_url")
        .in("id", senderIds)

      const map: Record<string, SenderProfile> = {}
      for (const profile of profiles || []) {
        map[String(profile.id)] = profile as SenderProfile
      }
      setSendersById(map)
    } else {
      setSendersById({})
    }

    setLoading(false)
  }, [userId])

  useEffect(() => {
    if (!userId) return
    void fetchNotifications()
  }, [userId, fetchNotifications])

  const listItems = useMemo(
    () => buildNotificationListItems(notifications),
    [notifications]
  )

  const sections = useMemo(
    () => groupItemsByTimeSection(listItems),
    [listItems]
  )

  const unreadCount = useMemo(
    () => listItems.filter((item) => itemIsUnread(item)).length,
    [listItems]
  )

  async function markIdsRead(ids: string[]) {
    if (!userId || ids.length === 0) return

    const { error } = await supabase
      .from("notifications")
      .update({ read: true })
      .eq("user_id", userId)
      .in("id", ids)
      .eq("read", false)

    if (error) {
      logNotificationsQueryError("mark read", error, {
        userId,
        columns: "update read = true",
      })
      return
    }

    const idSet = new Set(ids)
    setNotifications((prev) =>
      prev.map((row) => (idSet.has(row.id) ? { ...row, read: true } : row))
    )
    window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  }

  async function markAllAsRead() {
    if (!userId) return

    const { error } = await supabase
      .from("notifications")
      .update({ read: true })
      .eq("user_id", userId)
      .in("type", [...ENGAGEMENT_TYPES])
      .eq("read", false)

    if (error) {
      logNotificationsQueryError("mark all read", error, {
        userId,
        columns: "update read = true",
      })
      return
    }

    setNotifications((prev) => prev.map((row) => ({ ...row, read: true })))
    window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  }

  async function clearAll() {
    if (!userId || clearing) return
    setClearing(true)

    const ok = await clearAllNotifications(supabase)
    if (!ok) {
      setClearing(false)
      return
    }

    setNotifications([])
    setSendersById({})
    setShowClearConfirm(false)
    setClearing(false)
  }

  async function dismissIds(ids: string[]) {
    if (!userId || ids.length === 0) return

    const idSet = new Set(ids)
    setDismissingIds((prev) => new Set([...prev, ...ids]))

    const ok = await dismissNotifications(supabase, ids)
    setDismissingIds((prev) => {
      const next = new Set(prev)
      for (const id of ids) next.delete(id)
      return next
    })

    if (!ok) return

    setNotifications((prev) => prev.filter((row) => !idSet.has(row.id)))
  }

  function renderItem(item: NotificationListItem) {
    const unread = itemIsUnread(item)
    const timestamp = itemCreatedAt(item)
    const href = getNotificationHref(
      item,
      { id: userId ?? "", username: ownerUsername },
      sendersById
    )

    if (item.kind === "like_group") {
      const names = item.senderIds
        .slice(0, 2)
        .map((id) => senderDisplayName(sendersById[id]))
      const title = formatLikeGroupMessage(names, item.totalLikes)

      return (
        <NotificationCard
          key={item.key}
          unread={unread}
          title={title}
          timestamp={timestamp}
          dismissing={item.notificationIds.some((id) => dismissingIds.has(id))}
          onDismiss={() => void dismissIds(item.notificationIds)}
          onClick={() => {
            void markIdsRead(item.notificationIds)
            router.push(href)
          }}
        />
      )
    }

    const n = item.notification
    const sender = n.sender_id ? sendersById[n.sender_id] : undefined
    const senderName = senderDisplayName(sender)

    let title = "New activity"
    let body: string | null = null

    if (n.type === "comment") {
      title = `${senderName} commented on your post`
      body = commentPreview(n.content)
    } else if (n.type === "room_join") {
      title = formatRoomJoinMessage(senderName)
    } else if (n.type === "message") {
      title = "New message"
      body =
        n.content && n.content.trim() !== ""
          ? n.content
          : "You received a new message"
    } else if (n.type === "follow") {
      title = formatFollowMessage(senderName)
    }

    return (
      <NotificationCard
        key={n.id}
        unread={unread}
        title={title}
        body={body}
        timestamp={timestamp}
        avatarUrl={
          n.type === "follow" || n.type === "room_join"
            ? sender?.avatar_url
            : undefined
        }
        dismissing={dismissingIds.has(n.id)}
        onDismiss={() => void dismissIds([n.id])}
        onClick={() => {
          void markIdsRead([n.id])
          router.push(href)
        }}
      />
    )
  }

  const hasAnyItems =
    sections.today.length + sections.yesterday.length + sections.earlier.length >
    0

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="flex min-h-[50vh] items-center justify-center text-sm text-gray-400">
          Loading notifications…
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />

      <div className="w-full text-white px-2 pb-3 pt-0 md:px-4 md:pb-10">
        <div className="relative z-0 mx-auto mt-2.5 flex w-full max-w-xl flex-col gap-3 px-1 md:gap-4 md:px-2">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">
              Activity
            </p>
            <h1 className="mt-0.5 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
              Notifications
            </h1>
            <p className="mt-1 text-sm text-gray-400">
              Likes, comments, follows, and trade room activity.
            </p>
          </div>

          {hasAnyItems ? (
            <div className="flex flex-wrap gap-2">
              {unreadCount > 0 ? (
                <button
                  type="button"
                  onClick={() => void markAllAsRead()}
                  className="rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-gray-200 transition hover:bg-white/10"
                >
                  Mark all as read
                </button>
              ) : null}
              <button
                type="button"
                onClick={() => setShowClearConfirm(true)}
                className="rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-gray-200 transition hover:bg-white/10"
              >
                Clear all notifications
              </button>
            </div>
          ) : null}

          {!hasAnyItems ? (
            <EmptyState
              title="No notifications yet"
              description={
                loadError ??
                "When someone likes or comments on your posts, follows you, or joins your trade room, it will show up here."
              }
              action={
                <Link
                  href="/feed"
                  className="text-sm font-medium text-blue-300 hover:text-blue-200"
                >
                  Browse the feed →
                </Link>
              }
              className="py-10"
            />
          ) : (
            (["today", "yesterday", "earlier"] as TimeSection[]).map(
              (section) =>
                sections[section].length > 0 ? (
                  <section key={section} className="space-y-2">
                    <h2 className="text-sm font-semibold text-blue-300">
                      {SECTION_LABELS[section]}
                    </h2>
                    <div className="space-y-2">
                      {sections[section].map((item) => renderItem(item))}
                    </div>
                  </section>
                ) : null
            )
          )}
        </div>
      </div>

      <Modal
        open={showClearConfirm}
        onClose={() => {
          if (!clearing) setShowClearConfirm(false)
        }}
        title="Clear all notifications"
        size="sm"
        footer={
          <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <button
              type="button"
              disabled={clearing}
              onClick={() => setShowClearConfirm(false)}
              className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={clearing}
              onClick={() => void clearAll()}
              className="rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-red-500 disabled:opacity-50"
            >
              {clearing ? "Clearing…" : "Clear"}
            </button>
          </div>
        }
      >
        <p className="text-sm text-gray-300">
          Are you sure you want to clear all notifications? This cannot be undone.
        </p>
      </Modal>
    </>
  )
}
