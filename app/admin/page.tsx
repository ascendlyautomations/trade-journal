"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "../components/Navbar"
import { type AdminAuditFeedItem, fetchAdminRecentAudit } from "@/lib/adminAnalytics"
import {
  type AdminAffiliateApplicationCounts,
  fetchAdminAffiliateApplicationCounts,
} from "@/lib/affiliateAdmin"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import { supabase } from "@/lib/supabaseClient"

function AdminModuleCard({
  href,
  title,
  description,
  badge,
  variant = "default",
}: {
  href: string
  title: string
  description: string
  badge?: React.ReactNode
  variant?: "default" | "emerald" | "blue"
}) {
  const border =
    variant === "emerald"
      ? "border-emerald-500/30 bg-emerald-500/10 hover:bg-emerald-500/20 hover:border-emerald-400/50"
      : variant === "blue"
        ? "border-blue-500/30 bg-blue-500/10 hover:bg-blue-500/20 hover:border-blue-400/50"
        : "border-white/10 bg-white/5 hover:bg-white/10 hover:border-white/20"
  return (
    <Link href={href} className={`rounded-xl border p-5 transition ${border}`}>
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">{title}</h2>
        {badge}
      </div>
      <p className="mt-2 text-sm text-gray-300">{description}</p>
    </Link>
  )
}

export default function AdminPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)
  const [allowed, setAllowed] = useState(false)
  const [unviewedFeedbackCount, setUnviewedFeedbackCount] = useState<number>(0)
  const [unviewedSupportCount, setUnviewedSupportCount] = useState<number>(0)
  const [affiliateApplicationCounts, setAffiliateApplicationCounts] =
    useState<AdminAffiliateApplicationCounts | null>(null)
  const [auditPreview, setAuditPreview] = useState<AdminAuditFeedItem[]>([])
  const [auditError, setAuditError] = useState<string | null>(null)

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

        const { data: auditRows, error: auditErr } = await fetchAdminRecentAudit(supabase, 8)
        if (!cancelled) {
          if (auditErr) setAuditError(auditErr.message)
          else setAuditError(null)
          setAuditPreview(auditRows)
        }

        const { counts: affCounts, error: affCountErr } = await fetchAdminAffiliateApplicationCounts(
          supabase
        )
        if (!cancelled) {
          if (affCountErr) {
            console.debug("[admin] affiliate application counts RPC:", affCountErr.message)
            setAffiliateApplicationCounts(null)
          } else if (affCounts) {
            setAffiliateApplicationCounts(affCounts)
          } else {
            setAffiliateApplicationCounts(null)
          }
        }

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
        <div className="mx-auto max-w-6xl space-y-8">
          <div>
            <h1 className="text-2xl md:text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
              Admin Dashboard
            </h1>
            <p className="mt-1 text-sm text-gray-400">Choose a module. Queues and analytics open on dedicated pages.</p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <AdminModuleCard
              href="/admin/analytics"
              title="Analytics"
              description="Users, activity, content volume, and daily trend charts."
            />
            <AdminModuleCard
              href="/admin/users"
              title="Users"
              description="Search profiles, view activity, ban or unban accounts."
            />
            <AdminModuleCard href="/admin/reports" title="Reports" description="Trading reports and health metrics." />
            <AdminModuleCard href="/admin/moderation" title="Moderation" description="Content review and community tools." />
            <AdminModuleCard
              href="/admin/support"
              title="Support"
              description="Async support tickets and triage queues."
              variant="blue"
              badge={
                <span className="rounded bg-blue-500 px-2 py-0.5 text-xs font-semibold text-white tabular-nums">
                  {unviewedSupportCount} unviewed
                </span>
              }
            />
            <AdminModuleCard
              href="/admin/feedback"
              title="Feedback"
              description="Product feedback submissions and review state."
              variant="emerald"
              badge={
                <span className="rounded bg-emerald-500 px-2 py-0.5 text-xs font-semibold text-white">
                  {unviewedFeedbackCount} unviewed
                </span>
              }
            />
            <AdminModuleCard
              href="/admin/affiliates"
              title="Affiliate Applications"
              description="Review and manage affiliate program applications."
              variant="blue"
              badge={
                affiliateApplicationCounts ? (
                  <div className="flex flex-col items-end gap-0.5 text-right">
                    <span
                      className={[
                        "rounded px-2 py-0.5 text-xs font-semibold tabular-nums text-white",
                        affiliateApplicationCounts.pending > 0
                          ? "bg-amber-500 shadow-sm shadow-amber-500/25 ring-1 ring-amber-300/40"
                          : "bg-white/15",
                      ].join(" ")}
                    >
                      {affiliateApplicationCounts.pending} pending
                    </span>
                    <span className="max-w-[12rem] text-[10px] leading-tight text-gray-400">
                      {affiliateApplicationCounts.approved} approved · {affiliateApplicationCounts.rejected}{" "}
                      rejected · {affiliateApplicationCounts.total} total
                    </span>
                  </div>
                ) : (
                  <span className="text-[10px] text-gray-500">—</span>
                )
              }
            />
            <AdminModuleCard
              href="/admin/activity"
              title="Recent admin activity"
              description="Full audit log of moderation actions."
              variant="default"
            />
          </div>

          <section className="rounded-xl border border-white/10 bg-white/5 p-5">
            <div className="flex items-center justify-between gap-2">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">Latest audit events</h2>
              <Link href="/admin/activity" className="text-xs text-blue-300 hover:text-blue-200">
                View all
              </Link>
            </div>
            {auditError ? (
              <p className="mt-2 text-xs text-amber-200/90">
                Audit preview unavailable until DB migration is applied: {auditError}
              </p>
            ) : null}
            {!auditPreview.length && !auditError ? (
              <p className="mt-3 text-sm text-gray-500">No audit events yet.</p>
            ) : (
              <ul className="mt-3 space-y-2">
                {auditPreview.map((r) => (
                  <li key={r.id} className="flex flex-wrap items-baseline justify-between gap-2 text-sm">
                    <span className="text-gray-200">
                      <span className="font-medium text-emerald-300">{r.action}</span>
                      <span className="text-gray-500"> · </span>
                      <span className="text-gray-400">{r.admin_email || r.admin_user_id}</span>
                      {r.target_email || r.target_user_id ? (
                        <span className="text-gray-500">
                          {" "}
                          → {r.target_email || r.target_user_id}
                        </span>
                      ) : null}
                    </span>
                    <span className="text-xs text-gray-500 tabular-nums">
                      {r.created_at ? new Date(r.created_at).toLocaleString() : ""}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </div>
    </>
  )
}
