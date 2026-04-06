"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

type GroupedNotification = {
  key: string
  trade_id: string | null
  type: string
  users: Array<{ username?: string | null; avatar_url?: string | null }>
  latest: string
  notificationIds: string[]
  fallbackText: string | null
}

function normalizeSender(raw: any) {
  if (!raw) return null
  const row = Array.isArray(raw) ? raw[0] : raw
  return row as { username?: string | null; avatar_url?: string | null } | null
}

function buildGroupedNotifications(rows: any[]): GroupedNotification[] {
  const map = new Map<
    string,
    {
      trade_id: string | null
      type: string
      users: Array<{ username?: string | null; avatar_url?: string | null }>
      seenSender: Set<string>
      latest: string
      notificationIds: string[]
      fallbackText: string | null
    }
  >()

  for (const n of rows) {
    const tid =
      n.trade_id != null && String(n.trade_id).trim() !== ""
        ? String(n.trade_id)
        : null
    const key = tid ? `${tid}-${n.type}` : `__single__${n.id}`

    if (!map.has(key)) {
      map.set(key, {
        trade_id: tid,
        type: n.type,
        users: [],
        seenSender: new Set<string>(),
        latest: n.created_at,
        notificationIds: [],
        fallbackText: null,
      })
    }

    const g = map.get(key)!
    g.notificationIds.push(n.id)

    if (new Date(n.created_at).getTime() > new Date(g.latest).getTime()) {
      g.latest = n.created_at
    }

    const sid = n.sender_id != null ? String(n.sender_id) : ""
    const profile = normalizeSender(n.sender)
    if (sid) {
      if (!g.seenSender.has(sid)) {
        g.seenSender.add(sid)
        g.users.push(profile || { username: null })
      }
    } else if (profile) {
      g.users.push(profile)
    }

    const c = n.content != null ? String(n.content).trim() : ""
    if (c !== "" && !g.fallbackText) g.fallbackText = c
  }

  const out: GroupedNotification[] = []
  for (const [key, v] of map) {
    out.push({
      key,
      trade_id: v.trade_id,
      type: v.type,
      users: v.users,
      latest: v.latest,
      notificationIds: v.notificationIds,
      fallbackText: v.fallbackText,
    })
  }

  out.sort(
    (a, b) => new Date(b.latest).getTime() - new Date(a.latest).getTime()
  )
  return out
}

function displayName(u: { username?: string | null } | null | undefined) {
  const t = u?.username != null ? String(u.username).trim() : ""
  return t !== "" ? t : "User"
}

function formatUsers(
  users: Array<{ username?: string | null; avatar_url?: string | null }>
) {
  const names = users.map(displayName).filter(Boolean)
  if (names.length === 0) return "Someone"
  if (names.length === 1) return names[0]
  if (names.length === 2) return `${names[0]} and ${names[1]}`
  return `${names[0]}, ${names[1]} + ${names.length - 2} others`
}

function firstAvatar(
  users: Array<{ username?: string | null; avatar_url?: string | null }>
) {
  for (const u of users) {
    const a = u?.avatar_url != null ? String(u.avatar_url).trim() : ""
    if (a !== "" && a !== "null") return u.avatar_url
  }
  return null
}

export default function NotificationsPage() {
  const router = useRouter()
  const [user, setUser] = useState<{ id: string } | null>(null)
  const [notifications, setNotifications] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const groupedNotifications = useMemo(
    () => buildGroupedNotifications(notifications),
    [notifications]
  )

  useEffect(() => {
    let cancelled = false

    async function initUser() {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (cancelled) return
      if (!session?.user) {
        router.push("/login")
        return
      }
      setUser(session.user)
    }

    void initUser()
    return () => {
      cancelled = true
    }
  }, [router])

  const fetchNotifications = useCallback(async () => {
    if (!user?.id) return

    setLoading(true)

    const { error: markReadErr } = await supabase
      .from("notifications")
      .update({ read: true })
      .eq("user_id", user.id)
      .eq("read", false)

    if (markReadErr) {
      console.error("Mark notifications read error:", markReadErr)
    }

    window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))

    const { data, error } = await supabase
      .from("notifications")
      .select(
        `
        *,
        sender:profiles!sender_id (
          username,
          avatar_url
        )
      `
      )
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })

    if (error) {
      console.error("Fetch notifications error:", error?.message, error)
      setNotifications([])
      setLoading(false)
      return
    }

    setNotifications(data || [])
    setLoading(false)
  }, [user?.id])

  useEffect(() => {
    if (!user?.id) return
    void fetchNotifications()
  }, [user?.id, fetchNotifications])

  const openTrade = (tradeId: string | null) => {
    if (!tradeId) return
    router.push(`/trade/${tradeId}`)
  }

  async function onGroupedClick(g: GroupedNotification) {
    if (g.notificationIds.length > 0) {
      const { error } = await supabase
        .from("notifications")
        .update({ read: true })
        .in("id", g.notificationIds)

      if (error) {
        console.error("Mark notification read error:", error)
      } else {
        const idSet = new Set(g.notificationIds)
        setNotifications((prev) =>
          prev.map((x) => (idSet.has(x.id) ? { ...x, read: true } : x))
        )
      }
    }

    if (g.trade_id) {
      openTrade(g.trade_id)
    }
  }

  function groupBody(g: GroupedNotification) {
    if (g.type === "like") {
      return <>❤️ {formatUsers(g.users)} liked your trade</>
    }
    if (g.type === "comment") {
      return <>💬 {formatUsers(g.users)} commented on your trade</>
    }
    if (g.fallbackText) {
      return <>{g.fallbackText}</>
    }
    return <>Notification</>
  }

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
          <div>Loading...</div>
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-6">
        <div className="max-w-xl mx-auto space-y-4">
          <h1 className="text-2xl font-semibold text-center bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Notifications
          </h1>

          {groupedNotifications.length === 0 ? (
            <div className="text-gray-400 text-center mt-10">
              No notifications yet
            </div>
          ) : (
            groupedNotifications.map((g) => {
              const opensTrade = Boolean(g.trade_id)
              return (
                <div
                  key={g.key}
                  role="button"
                  tabIndex={0}
                  onClick={() => void onGroupedClick(g)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault()
                      void onGroupedClick(g)
                    }
                  }}
                  className="p-3 bg-[#1e293b] rounded-lg mb-2 cursor-pointer hover:bg-[#334155] transition-colors"
                  title={opensTrade ? "Open trade" : undefined}
                >
                  <div className="flex items-center gap-3">
                    <img
                      src={firstAvatar(g.users) || "/default-avatar.png"}
                      alt=""
                      className="w-8 h-8 rounded-full object-cover shrink-0 bg-white/10"
                    />
                    <p className="text-white text-sm min-w-0">{groupBody(g)}</p>
                  </div>
                </div>
              )
            })
          )}
        </div>
      </div>
    </>
  )
}
