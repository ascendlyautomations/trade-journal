"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

type NotificationRow = {
  id: string
  user_id: string
  type: string
  message: string | null
  created_at: string
  read: boolean
  sender_id: string | null
  trade_id: string | null
}

function timeAgo(ts: string): string {
  const t = new Date(ts).getTime()
  if (!Number.isFinite(t)) return ""
  const s = Math.max(0, Math.floor((Date.now() - t) / 1000))
  if (s < 60) return "just now"
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  if (s < 604800) return `${Math.floor(s / 86400)}d ago`
  return new Date(ts).toLocaleDateString()
}

export default function NotificationsPage() {
  const router = useRouter()
  const [user, setUser] = useState<{ id: string } | null>(null)
  const [notifications, setNotifications] = useState<NotificationRow[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    async function initUser() {
      const { data, error } = await supabase.auth.getUser()
      if (cancelled) return
      if (error || !data?.user) {
        console.error("[notifications] auth user load failed", {
          message: error?.message ?? null,
          details: error?.details ?? null,
          hint: error?.hint ?? null,
          code: error?.code ?? null,
        })
        router.push("/login")
        return
      }
      console.debug("[notifications] current user loaded", { userId: data.user.id })
      setUser({ id: data.user.id })
    }

    void initUser()
    return () => {
      cancelled = true
    }
  }, [router])

  const fetchNotifications = useCallback(async () => {
    if (!user?.id) return
    setLoading(true)
    setLoadError(null)

    const fetchQuery = "id,user_id,type,message,created_at,read,sender_id,trade_id"
    console.debug("[notifications] fetching message notifications", {
      userId: user.id,
      query: fetchQuery,
    })

    const { data, error } = await supabase
      .from("notifications")
      .select(fetchQuery)
      .eq("user_id", user.id)
      .eq("type", "message")
      .order("created_at", { ascending: false })

    if (error) {
      console.error("[notifications] fetch message notifications failed", {
        query: fetchQuery,
        userId: user.id,
        message: error.message,
        details: error.details,
        hint: error.hint,
        code: error.code,
      })
      setNotifications([])
      setLoadError("Could not load notifications right now.")
      setLoading(false)
      return
    }

    const rows = (data || []) as NotificationRow[]
    const unreadCount = rows.filter((r) => !r.read).length
    console.debug("[notifications] message notifications fetched", {
      userId: user.id,
      rowCount: rows.length,
      unreadCount,
      firstRowUserId: rows[0]?.user_id ?? null,
      types: Array.from(new Set(rows.map((r) => r.type))),
      rows,
    })
    setNotifications(rows)
    setLoading(false)
  }, [user?.id])

  useEffect(() => {
    if (!user?.id) return
    void fetchNotifications()
  }, [user?.id, fetchNotifications])

  const unreadCount = useMemo(() => {
    return notifications.filter((n) => !n.read).length
  }, [notifications])

  async function markAllAsRead() {
    if (!user?.id) return
    const { error } = await supabase
      .from("notifications")
      .update({ read: true })
      .eq("user_id", user.id)
      .eq("type", "message")
      .eq("read", false)

    if (error) {
      console.error("[notifications] mark all message notifications read failed", {
        userId: user.id,
        message: error.message,
        details: error.details,
        hint: error.hint,
        code: error.code,
      })
      return
    }

    setNotifications((prev) => prev.map((n) => ({ ...n, read: true })))
    console.debug("[notifications] mark all message notifications read success", {
      userId: user.id,
      updatedCount: notifications.filter((n) => !n.read).length,
    })
    window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
  }

  async function onNotificationClick(n: NotificationRow) {
    if (!n.read) {
      const { error } = await supabase
        .from("notifications")
        .update({ read: true })
        .eq("id", n.id)
        .eq("user_id", user?.id ?? "")
        .eq("type", "message")
      if (error) {
        console.error("[notifications] mark single message read failed", {
          notificationId: n.id,
          userId: user?.id ?? null,
          message: error.message,
          details: error.details,
          hint: error.hint,
          code: error.code,
        })
      } else {
        console.debug("[notifications] mark single message read success", {
          notificationId: n.id,
        })
        setNotifications((prev) =>
          prev.map((x) => (x.id === n.id ? { ...x, read: true } : x))
        )
        window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
      }
    }

    router.push("/messages")
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
        <div className="mx-auto max-w-xl space-y-4">
          <h1 className="text-center text-2xl font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Message Notifications
          </h1>

          {unreadCount > 0 ? (
            <button
              type="button"
              onClick={() => void markAllAsRead()}
              className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-gray-200 hover:bg-white/10"
            >
              Mark all messages as read
            </button>
          ) : null}

          {notifications.length === 0 ? (
            <div className="mt-10 text-center text-gray-400">
              {loadError ?? "No message notifications yet"}
            </div>
          ) : (
            notifications.map((n) => (
              <div
                key={n.id}
                role="button"
                tabIndex={0}
                onClick={() => void onNotificationClick(n)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault()
                    void onNotificationClick(n)
                  }
                }}
                className={`mb-2 cursor-pointer rounded-lg p-3 transition-colors ${
                  !n.read
                    ? "bg-[#26364d] ring-1 ring-blue-400/50 hover:bg-[#334155]"
                    : "bg-[#1e293b] hover:bg-[#334155]"
                }`}
              >
                <div className="space-y-1">
                  <p className={`text-sm ${n.read ? "text-gray-200" : "font-semibold text-white"}`}>
                    New message
                  </p>
                  <p className="text-xs text-gray-300">
                    {n.message && String(n.message).trim() !== ""
                      ? String(n.message)
                      : "You received a new message"}
                  </p>
                  <p className="text-[11px] uppercase tracking-wide text-gray-500">
                    {timeAgo(n.created_at)} • {n.read ? "Read" : "Unread"}
                  </p>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  )
}
