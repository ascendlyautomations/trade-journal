"use client"

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import {
  ProfileAvatarLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"
import FollowRequestsPanel from "../components/FollowRequestsPanel"
import EmptyState from "../components/ui/EmptyState"
import Modal from "../components/ui/Modal"
import { clearAllNotifications, dismissNotifications } from "@/lib/followNotifications"
import { formatEST } from "@/lib/formatEST"
import { NOTIFICATION_ENGAGEMENT_TYPES } from "@/lib/notificationEngagementTypes"
import {
  buildGroupedNotificationCards,
  commentPreview,
  filterGroupedCardsByTab,
  formatCommentGroupTitle,
  formatFollowGroupMessage,
  formatFollowRequestGroupMessage,
  formatLikeGroupMessage,
  formatRoomJoinMessage,
  getGroupedNotificationHref,
  getNotificationTimeSection,
  groupCardsByTimeSection,
  groupedCardCreatedAt,
  groupedCardIsUnread,
  groupedCardNotificationIds,
  senderDisplayName,
  type GroupedNotificationCard,
  type NotificationCenterTab,
  type NotificationRecord,
  type SenderProfile,
  type TimeSection,
} from "@/lib/notificationsDisplay"

const NOTIFICATIONS_TABLE = "notifications"

const NOTIFICATION_SELECT =
  "id, user_id, sender_id, type, post_id, trade_id, content, read, created_at"

const ENGAGEMENT_TYPES = NOTIFICATION_ENGAGEMENT_TYPES

const TABS: { id: NotificationCenterTab; label: string }[] = [
  { id: "all", label: "All" },
  { id: "likes", label: "Likes" },
  { id: "comments", label: "Comments" },
  { id: "followers", label: "Followers" },
]

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

/** React list key — must be unique across like/comment/follow/room_join cards. */
function cardStableKey(card: GroupedNotificationCard): string {
  switch (card.kind) {
    case "like_group":
      return `like:${card.key}`
    case "comment_group":
      return `comment:${card.key}`
    case "follow_group":
    case "follow_request_group":
      return card.key
    case "room_join":
      return `room_join:${card.notification.id}`
  }
}

function GroupedNotificationCardView({
  card,
  sendersById,
  expanded,
  onToggleExpand,
  unread,
  timestamp,
  dismissing,
  onNavigate,
  onDismiss,
}: {
  card: GroupedNotificationCard
  sendersById: Record<string, SenderProfile>
  expanded: boolean
  onToggleExpand: () => void
  unread: boolean
  timestamp: string
  dismissing: boolean
  onNavigate: () => void
  onDismiss: () => void
}) {
  let title = "New activity"
  let expandable = false
  let expandedContent: ReactNode = null
  let avatarUrl: string | null | undefined

  if (card.kind === "like_group") {
    const names = card.senderIds
      .slice(0, 2)
      .map((id) => senderDisplayName(sendersById[id]))
    title = formatLikeGroupMessage(
      names,
      card.totalLikes,
      card.post_id,
      card.trade_id
    )
  } else if (card.kind === "comment_group") {
    expandable = true
    title = formatCommentGroupTitle(
      card.totalComments,
      card.post_id,
      card.trade_id
    )
    expandedContent = (
      <ul className="mt-2 space-y-2 border-t border-white/10 pt-2">
        {card.comments.map((entry) => {
          const sender = entry.senderId
            ? sendersById[entry.senderId]
            : undefined
          const name = senderDisplayName(sender)
          const preview = commentPreview(
            entry.content,
            card.post_id,
            card.trade_id
          )
          return (
            <li key={entry.id} className="text-xs text-gray-300">
              {entry.senderId ? (
                <ProfileUsernameLink
                  userId={entry.senderId}
                  username={sender?.username}
                  className="font-medium text-gray-200"
                >
                  {name}
                </ProfileUsernameLink>
              ) : (
                <span className="font-medium text-gray-200">{name}</span>
              )}
              <span className="text-gray-500">: </span>
              {preview}
            </li>
          )
        })}
      </ul>
    )
  } else if (card.kind === "follow_group") {
    expandable = true
    const names = card.senderIds
      .slice(0, 2)
      .map((id) => senderDisplayName(sendersById[id]))
    title = formatFollowGroupMessage(names, card.totalFollows)
    expandedContent = (
      <ul className="mt-2 space-y-1.5 border-t border-white/10 pt-2">
        {card.senderIds.map((id) => {
          const sender = sendersById[id]
          return (
            <li
              key={id}
              className="flex items-center gap-2 text-xs text-gray-200"
            >
              <ProfileAvatarLink
                userId={id}
                username={sender?.username}
                src={sender?.avatar_url}
                stopPropagation
                imgClassName="h-6 w-6 rounded-full object-cover ring-1 ring-white/10"
              />
              <ProfileUsernameLink
                userId={id}
                username={sender?.username}
                className="text-xs text-gray-200"
              >
                {senderDisplayName(sender)}
              </ProfileUsernameLink>
            </li>
          )
        })}
      </ul>
    )
  } else if (card.kind === "follow_request_group") {
    expandable = true
    const names = card.senderIds
      .slice(0, 2)
      .map((id) => senderDisplayName(sendersById[id]))
    title = formatFollowRequestGroupMessage(names, card.totalRequests)
    expandedContent = (
      <ul className="mt-2 space-y-1.5 border-t border-white/10 pt-2">
        {card.senderIds.map((id) => {
          const sender = sendersById[id]
          return (
            <li
              key={id}
              className="flex items-center gap-2 text-xs text-gray-200"
            >
              <ProfileAvatarLink
                userId={id}
                username={sender?.username}
                src={sender?.avatar_url}
                stopPropagation
                imgClassName="h-6 w-6 rounded-full object-cover ring-1 ring-white/10"
              />
              <ProfileUsernameLink
                userId={id}
                username={sender?.username}
                className="text-xs text-gray-200"
              >
                {senderDisplayName(sender)}
              </ProfileUsernameLink>
            </li>
          )
        })}
      </ul>
    )
  } else if (card.kind === "room_join") {
    const sender = card.notification.sender_id
      ? sendersById[card.notification.sender_id]
      : undefined
    title = formatRoomJoinMessage(senderDisplayName(sender))
    avatarUrl = sender?.avatar_url
  }

  return (
    <div
      className={`rounded-xl border p-3 transition ${
        unread
          ? "border-blue-400/40 bg-white/10 ring-1 ring-blue-400/30"
          : "border-white/10 bg-white/5"
      }`}
    >
      <div className="flex items-start gap-2 sm:gap-3">
        {avatarUrl != null && card.kind === "room_join" && card.notification.sender_id ? (
          <div className="relative shrink-0">
            <ProfileAvatarLink
              userId={card.notification.sender_id}
              username={
                card.notification.sender_id
                  ? sendersById[card.notification.sender_id]?.username
                  : null
              }
              src={avatarUrl}
              stopPropagation
              imgClassName="h-9 w-9 rounded-full object-cover ring-2 ring-white/10"
            />
            {unread ? (
              <span
                className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full border-2 border-[#0f172a] bg-blue-400"
                aria-hidden
              />
            ) : null}
          </div>
        ) : avatarUrl != null ? (
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

        <div className="min-w-0 flex-1 space-y-1">
          <div className="flex items-start gap-1">
            <button
              type="button"
              onClick={onNavigate}
              className="min-w-0 flex-1 rounded-lg text-left outline-none focus-visible:ring-2 focus-visible:ring-blue-400/50"
            >
              <p
                className={`text-sm ${unread ? "font-semibold text-white" : "text-gray-200"}`}
              >
                {title}
              </p>
              <p className="mt-1 text-[11px] uppercase tracking-wide text-gray-500">
                {timeAgo(timestamp)}
              </p>
            </button>
            {expandable ? (
              <button
                type="button"
                onClick={onToggleExpand}
                className="shrink-0 rounded-md p-1.5 text-gray-400 transition hover:bg-white/10 hover:text-white"
                aria-expanded={expanded}
                aria-label={expanded ? "Collapse" : "Expand"}
              >
                <span
                  className={`inline-block text-xs transition-transform ${
                    expanded ? "rotate-180" : ""
                  }`}
                >
                  ▼
                </span>
              </button>
            ) : null}
          </div>

          {expandable && expanded ? expandedContent : null}

          {expandable ? (
            <button
              type="button"
              onClick={onNavigate}
              className="text-xs font-medium text-blue-300 hover:text-blue-200"
            >
              View
              {card.kind === "follow_group"
                ? " followers"
                : card.kind === "follow_request_group"
                  ? " profile"
                  : ""}{" "}
              →
            </button>
          ) : null}
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
  const [ownerIsPrivate, setOwnerIsPrivate] = useState<boolean | null>(null)
  const [notifications, setNotifications] = useState<NotificationRecord[]>([])
  const [sendersById, setSendersById] = useState<Record<string, SenderProfile>>(
    {}
  )
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [showClearConfirm, setShowClearConfirm] = useState(false)
  const [clearing, setClearing] = useState(false)
  const [dismissingIds, setDismissingIds] = useState<Set<string>>(new Set())
  const [activeTab, setActiveTab] = useState<NotificationCenterTab>("all")
  const [expandedKeys, setExpandedKeys] = useState<Set<string>>(new Set())

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

      const { data: ownProfile, error: profileError } = await supabase
        .from("profiles")
        .select("username, is_private")
        .eq("id", data.user.id)
        .maybeSingle()

      if (!cancelled) {
        setOwnerUsername(ownProfile?.username ?? null)
        setOwnerIsPrivate(ownProfile?.is_private === true)
        console.info("[follow-requests] owner profile loaded", {
          userId: data.user.id,
          profileExists: Boolean(ownProfile),
          is_private: ownProfile?.is_private ?? null,
          profileError: profileError
            ? {
                code: profileError.code,
                message: profileError.message,
                details: profileError.details,
                hint: profileError.hint,
              }
            : null,
        })
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

  const groupedCards = useMemo(
    () => buildGroupedNotificationCards(notifications),
    [notifications]
  )

  const tabCards = useMemo(
    () => filterGroupedCardsByTab(groupedCards, activeTab),
    [groupedCards, activeTab]
  )

  const sections = useMemo(
    () => groupCardsByTimeSection(tabCards),
    [tabCards]
  )

  const unreadCount = useMemo(
    () => groupedCards.filter((card) => groupedCardIsUnread(card)).length,
    [groupedCards]
  )

  const showFollowRequestsPanel = Boolean(
    userId &&
      ownerIsPrivate === true &&
      (activeTab === "all" || activeTab === "followers")
  )

  useEffect(() => {
    console.info("[follow-requests] panel mount decision", {
      userId,
      profileIsPrivate: ownerIsPrivate,
      activeTab,
      mounted: showFollowRequestsPanel,
      reason: !userId
        ? "no_user"
        : ownerIsPrivate === null
          ? "profile_not_loaded"
          : ownerIsPrivate === false
            ? "not_private_account"
            : activeTab !== "all" && activeTab !== "followers"
              ? "tab_not_followers"
              : "mounted",
    })
  }, [userId, ownerIsPrivate, activeTab, showFollowRequestsPanel])

  const tabCounts = useMemo(() => {
    const likes = groupedCards.filter((c) => c.kind === "like_group").length
    const comments = groupedCards.filter((c) => c.kind === "comment_group").length
    const followers = groupedCards.filter(
      (c) => c.kind === "follow_group" || c.kind === "follow_request_group"
    ).length
    return { all: groupedCards.length, likes, comments, followers }
  }, [groupedCards])

  function toggleExpanded(key: string) {
    setExpandedKeys((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

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

  function renderCard(card: GroupedNotificationCard) {
    const key = cardStableKey(card)
    const ids = groupedCardNotificationIds(card)
    const href = getGroupedNotificationHref(
      card,
      { id: userId ?? "", username: ownerUsername },
      sendersById
    )

    return (
      <GroupedNotificationCardView
        key={key}
        card={card}
        sendersById={sendersById}
        expanded={expandedKeys.has(key)}
        onToggleExpand={() => toggleExpanded(key)}
        unread={groupedCardIsUnread(card)}
        timestamp={groupedCardCreatedAt(card)}
        dismissing={ids.some((id) => dismissingIds.has(id))}
        onNavigate={() => {
          void markIdsRead(ids)
          router.push(href)
        }}
        onDismiss={() => void dismissIds(ids)}
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
              Grouped likes, comments, follows, and trade room activity.
            </p>
          </div>

          <div className="-mx-1 overflow-x-auto px-1 scrollbar-thin">
            <div
              className="flex min-w-max gap-2 border-b border-white/10 pb-2"
              role="tablist"
              aria-label="Notification categories"
            >
              {TABS.map((tab) => {
                const count = tabCounts[tab.id]
                const selected = activeTab === tab.id
                return (
                  <button
                    key={tab.id}
                    type="button"
                    role="tab"
                    aria-selected={selected}
                    onClick={() => setActiveTab(tab.id)}
                    className={`shrink-0 rounded-full px-3.5 py-1.5 text-sm font-medium transition ${
                      selected
                        ? "bg-blue-500/25 text-white ring-1 ring-blue-400/40"
                        : "bg-white/5 text-gray-300 hover:bg-white/10 hover:text-white"
                    }`}
                  >
                    {tab.label}
                    {count > 0 ? (
                      <span className="ml-1.5 tabular-nums text-xs opacity-70">
                        {count}
                      </span>
                    ) : null}
                  </button>
                )
              })}
            </div>
          </div>

          {showFollowRequestsPanel && userId ? (
            <FollowRequestsPanel
              userId={userId}
              isPrivate={ownerIsPrivate === true}
              onResolved={() => void fetchNotifications()}
            />
          ) : null}

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
              title={
                activeTab === "all"
                  ? "No notifications yet"
                  : `No ${activeTab} notifications`
              }
              description={
                loadError ??
                (activeTab === "all"
                  ? "When someone likes or comments on your posts or trades, follows you, or joins your trade room, it will show up here."
                  : `Nothing in ${TABS.find((t) => t.id === activeTab)?.label ?? activeTab} right now.`)
              }
              action={
                activeTab === "all" ? (
                  <Link
                    href="/feed"
                    className="text-sm font-medium text-blue-300 hover:text-blue-200"
                  >
                    Browse the feed →
                  </Link>
                ) : undefined
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
                      {sections[section].map((card) => renderCard(card))}
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
