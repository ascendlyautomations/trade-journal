"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { type AdminAuditFeedItem, fetchAdminRecentAudit } from "@/lib/adminAnalytics"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { supabase } from "@/lib/supabaseClient"

export default function AdminActivityPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [rows, setRows] = useState<AdminAuditFeedItem[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const check = await getCurrentAdminCheckResult()
      if (!check.userId) {
        router.replace("/login")
        return
      }
      if (!check.isAdmin) {
        router.replace("/dashboard")
        return
      }
      if (!cancelled) {
        setAllowed(true)
        setChecking(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [router])

  useEffect(() => {
    if (!allowed) return
    let cancelled = false
    void (async () => {
      const { data, error: e } = await fetchAdminRecentAudit(supabase, 80)
      if (cancelled) return
      if (e) setError(e.message)
      setRows(data)
    })()
    return () => {
      cancelled = true
    }
  }, [allowed])

  if (checking || !allowed) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Checking admin access…
        </div>
      </>
    )
  }

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 text-gray-100 md:p-8">
        <div className="mx-auto max-w-4xl space-y-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h1 className="text-2xl font-bold text-blue-300 md:text-3xl">
              Admin activity
            </h1>
            <Link href="/admin" className="rounded bg-white/10 px-3 py-2 text-sm hover:bg-white/20">
              Back to Admin
            </Link>
          </div>
          <p className="text-sm text-gray-400">Recent moderation and audit events ({rows.length} loaded).</p>

          {error ? (
            <p className="text-sm text-red-300">
              {error} — apply migrations for <code className="rounded bg-black/30 px-1">admin_recent_audit</code>.
            </p>
          ) : null}

          <ul className="space-y-2">
            {rows.map((r) => (
              <li key={r.id} className="rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-sm">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <span className="font-medium text-emerald-300">{r.action}</span>
                  <span className="text-xs text-gray-500 tabular-nums">
                    {r.created_at ? new Date(r.created_at).toLocaleString() : "—"}
                  </span>
                </div>
                <p className="mt-1 text-xs text-gray-400">
                  By {r.admin_email || r.admin_user_id}
                  {r.target_user_id ? (
                    <>
                      {" "}
                      → target {r.target_email || r.target_user_id}
                    </>
                  ) : null}
                </p>
                {r.details && Object.keys(r.details).length > 0 ? (
                  <pre className="mt-2 max-h-24 overflow-auto rounded bg-black/30 p-2 text-xs text-gray-300">
                    {JSON.stringify(r.details, null, 2)}
                  </pre>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </>
  )
}
