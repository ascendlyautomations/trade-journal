"use client"

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

export default function NotificationsPage() {
  const router = useRouter()
  const [notifications, setNotifications] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadNotifications = useCallback(async (userId: string) => {
    const { data, error } = await supabase
      .from("notifications")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })

    if (error) {
      console.error("Notifications fetch error:", error)
      setNotifications([])
      return
    }

    setNotifications(data || [])
  }, [])

  useEffect(() => {
    let cancelled = false

    async function init() {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (!session?.user) {
        router.push("/login")
        return
      }
      if (cancelled) return

      const { error: markReadErr } = await supabase
        .from("notifications")
        .update({ read: true })
        .eq("user_id", session.user.id)
        .eq("read", false)

      if (markReadErr) {
        console.error("Mark notifications read error:", markReadErr)
      }

      window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))

      await loadNotifications(session.user.id)
      if (!cancelled) setLoading(false)
    }

    void init()

    return () => {
      cancelled = true
    }
  }, [router, loadNotifications])

  async function onNotificationClick(n: any) {
    const { error } = await supabase
      .from("notifications")
      .update({ read: true })
      .eq("id", n.id)

    if (error) {
      console.error("Mark notification read error:", error)
      return
    }

    setNotifications((prev) =>
      prev.map((x) => (x.id === n.id ? { ...x, read: true } : x))
    )
  }

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
          Loading…
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

          {notifications.length === 0 ? (
            <p className="text-center text-sm text-gray-400">No notifications yet.</p>
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
                className="p-3 bg-[#1e293b] rounded-lg mb-2 cursor-pointer"
              >
                <p className="text-white text-sm">{n.content}</p>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  )
}
