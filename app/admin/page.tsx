"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "../components/Navbar"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { supabase } from "@/lib/supabaseClient"

export default function AdminPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [unviewedFeedbackCount, setUnviewedFeedbackCount] = useState<number>(0)
  const [unviewedSupportCount, setUnviewedSupportCount] = useState<number>(0)

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const check = await getCurrentAdminCheckResult()

      if (process.env.NODE_ENV !== "production") {
        console.debug("[admin-check][/admin] resolved", {
          userId: check.userId,
          email: check.email,
          adminRow: check.row,
          error: check.error,
          isAdmin: check.isAdmin,
        })
      }

      if (!check.userId) {
        if (process.env.NODE_ENV !== "production") {
          console.debug("[admin-check][/admin] redirect login: no auth user")
        }
        router.replace("/login")
        return
      }

      if (!check.isAdmin) {
        if (process.env.NODE_ENV !== "production") {
          console.debug("[admin-check][/admin] redirect dashboard: not in admin_users", {
            userId: check.userId,
            row: check.row,
            error: check.error,
          })
        }
        router.replace("/dashboard")
        return
      }

      if (!cancelled) {
        const { count } = await supabase
          .from("feedback_submissions")
          .select("*", { count: "exact", head: true })
          .eq("viewed", false)
        if (!cancelled) setUnviewedFeedbackCount(count || 0)

        const { count: supportUnviewed } = await supabase
          .from("support_tickets")
          .select("*", { count: "exact", head: true })
          .eq("viewed", false)
        if (!cancelled) setUnviewedSupportCount(supportUnviewed || 0)
        setAllowed(true)
        setChecking(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [router])

  if (checking || !allowed) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white p-8">
          Checking admin access...
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-4 md:p-8">
        <div className="mx-auto max-w-6xl space-y-6">
          <h1 className="text-2xl md:text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Admin Dashboard
          </h1>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Link href="/admin/reports" className="rounded-xl border border-white/10 bg-white/5 p-5 transition hover:bg-white/10 hover:border-white/20">
              <h2 className="text-lg font-semibold">Reports</h2>
              <p className="mt-2 text-sm text-gray-300">Open trading reports and health metrics.</p>
            </Link>

            <Link
              href="/admin/support"
              className="rounded-xl border border-blue-500/30 bg-blue-500/10 p-5 transition hover:bg-blue-500/20 hover:border-blue-400/50"
            >
              <div className="flex items-center justify-between gap-3">
                <h2 className="text-lg font-semibold">Support</h2>
                <span className="rounded bg-blue-500 px-2 py-0.5 text-xs font-semibold text-white tabular-nums">
                  {unviewedSupportCount} unviewed
                </span>
              </div>
              <p className="mt-2 text-sm text-gray-200">Review async support tickets by queue and status.</p>
            </Link>

            <Link href="/admin/moderation" className="rounded-xl border border-white/10 bg-white/5 p-5 transition hover:bg-white/10 hover:border-white/20">
              <h2 className="text-lg font-semibold">Moderation</h2>
              <p className="mt-2 text-sm text-gray-300">Open moderation tools and content review.</p>
            </Link>

            <Link href="/admin/activity" className="rounded-xl border border-white/10 bg-white/5 p-5 transition hover:bg-white/10 hover:border-white/20">
              <h2 className="text-lg font-semibold">Recent Admin Activity</h2>
              <p className="mt-2 text-sm text-gray-300">Open recent events and admin actions.</p>
            </Link>

            <Link href="/admin/feedback" className="rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-5 transition hover:bg-emerald-500/20 hover:border-emerald-400/50 md:col-span-2">
              <div className="flex items-center justify-between gap-3">
                <h2 className="text-lg font-semibold">Feedback Submissions</h2>
                <span className="rounded bg-emerald-500 px-2 py-0.5 text-xs font-semibold text-white">
                  {unviewedFeedbackCount} unviewed
                </span>
              </div>
              <p className="mt-2 text-sm text-gray-200">
                Review user feedback in dedicated Unviewed/Viewed queues with detail editing.
              </p>
            </Link>
          </div>
        </div>
      </div>
    </>
  )
}

