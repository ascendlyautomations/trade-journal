"use client"

import { useCallback, useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { supabase } from "../../lib/supabaseClient"
import {
  recordedAffiliateEarnings,
  resolveRecordedAffiliateEarnings,
} from "@/lib/affiliateEarnings"
import { useToast } from "@/app/components/ui"

type ProfileRow = {
  id: string
  referral_code?: string | null
}

type ReferredProfile = {
  id: string
  username?: string | null
  subscription_status?: string | null
  created_at?: string | null
}

function formatJoinDate(raw: string | null | undefined): string {
  if (!raw) return "—"
  const d = new Date(raw)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}

function statusLabel(status: string | null | undefined): string {
  const s = String(status ?? "").toLowerCase().trim()
  if (!s) return "inactive"
  return s
}

function statusClass(status: string | null | undefined): string {
  const s = String(status ?? "").toLowerCase()
  if (s === "active") return "text-emerald-400"
  if (s === "trialing") return "text-amber-400"
  return "text-gray-400"
}

export default function ReferralsPage() {
  const toast = useToast()
  const router = useRouter()
  const [loading, setLoading] = useState(true)
  const [profile, setProfile] = useState<ProfileRow | null>(null)
  const [referrals, setReferrals] = useState<ReferredProfile[]>([])
  const [ledgerTotal, setLedgerTotal] = useState(0)
  const [copyDone, setCopyDone] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      setLoading(false)
      router.push("/login")
      return
    }

    const { data: prof, error: profErr } = await supabase
      .from("profiles")
      .select("id, referral_code, referral_earnings")
      .eq("id", user.id)
      .single()

    if (profErr || !prof) {
      console.error(profErr)
      setProfile(null)
      setReferrals([])
      setLedgerTotal(0)
      setLoading(false)
      return
    }

    setProfile(prof as ProfileRow)

    const { data: ledger, error: ledgerErr } = await supabase
      .from("referrals")
      .select("amount_earned")
      .eq("referrer_user_id", user.id)

    if (ledgerErr) {
      console.error("referrals ledger:", ledgerErr)
      setLedgerTotal(recordedAffiliateEarnings(prof.referral_earnings))
    } else {
      setLedgerTotal(
        resolveRecordedAffiliateEarnings(
          (prof as { referral_earnings?: number | null }).referral_earnings,
          ledger
        )
      )
    }

    const code = prof.referral_code != null ? String(prof.referral_code).trim() : ""
    if (!code) {
      setReferrals([])
      setLoading(false)
      return
    }

    const { data: refRows, error: refErr } = await supabase
      .from("profiles")
      .select("id, username, subscription_status, created_at")
      .eq("referred_by", code)

    if (refErr) {
      console.error(refErr)
      setReferrals([])
    } else {
      setReferrals((refRows as ReferredProfile[]) ?? [])
    }

    setLoading(false)
  }, [router])

  useEffect(() => {
    void load()
  }, [load])

  const referralCode =
    profile?.referral_code != null ? String(profile.referral_code).trim() : ""

  const referralLink =
    typeof window !== "undefined" && referralCode
      ? `${window.location.origin}/login?ref=${encodeURIComponent(referralCode)}`
      : ""

  const totalReferrals = referrals.length
  const activeReferrals = referrals.filter(
    (r) => String(r.subscription_status ?? "").toLowerCase() === "active"
  ).length
  const totalEarnings = ledgerTotal

  async function copyLink() {
    if (!referralLink) return
    try {
      await navigator.clipboard.writeText(referralLink)
      setCopyDone(true)
      window.setTimeout(() => setCopyDone(false), 2000)
    } catch (e) {
      console.error(e)
      toast.error("Could not copy link")
    }
  }

  if (loading) {
    return (
      <>
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
          Loading…
        </div>
      </>
    )
  }

  return (
    <>

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 text-white sm:px-6 lg:px-8">
        <div className="mx-auto max-w-5xl">
          <div className="mb-8 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h1 className="text-2xl font-bold text-white sm:text-3xl">
                Referral stats
              </h1>
              <p className="mt-1 text-sm text-gray-400">
                Track earnings, invites, and who joined with your link
              </p>
            </div>
            <Link
              href="/affiliate/dashboard"
              className="text-sm text-blue-300 hover:text-blue-200"
            >
              Affiliate dashboard →
            </Link>
          </div>

          <div className="mb-8 grid gap-4 sm:grid-cols-3">
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-sm">
              <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
                Total earnings
              </p>
              <p className="mt-2 text-2xl font-bold text-emerald-400">
                ${totalEarnings.toFixed(2)}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-sm">
              <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
                Total referrals
              </p>
              <p className="mt-2 text-2xl font-bold text-white">{totalReferrals}</p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-sm">
              <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
                Active referrals
              </p>
              <p className="mt-2 text-2xl font-bold text-blue-300">{activeReferrals}</p>
            </div>
          </div>

          <div className="mb-8 rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
              Your referral link
            </h2>
            <p className="mt-1 text-sm text-gray-400">
              Share this link — signups will attribute to your account when they register.
            </p>
            {!referralCode ? (
              <p className="mt-4 text-sm text-amber-200/90">
                You don&apos;t have a referral code on your profile yet. Visit{" "}
                <Link href="/affiliate/dashboard" className="underline hover:text-white">
                  Affiliate
                </Link>{" "}
                to get set up.
              </p>
            ) : (
              <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center">
                <input
                  readOnly
                  value={referralLink}
                  className="min-w-0 flex-1 rounded-xl border border-white/10 bg-black/30 px-3 py-2.5 font-mono text-sm text-gray-200"
                />
                <button
                  type="button"
                  onClick={() => void copyLink()}
                  className="shrink-0 rounded-xl bg-emerald-500 px-5 py-2.5 text-sm font-semibold text-white hover:bg-emerald-600"
                >
                  {copyDone ? "Copied!" : "Copy link"}
                </button>
              </div>
            )}
          </div>

          <div className="rounded-xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
              Referred users
            </h2>
            <p className="mt-1 text-sm text-gray-400">
              People who signed up with your referral code
            </p>

            {referrals.length === 0 ? (
              <p className="mt-6 text-center text-sm text-gray-500">
                No referrals yet. Share your link to get started.
              </p>
            ) : (
              <ul className="mt-4 divide-y divide-white/10">
                {referrals.map((r) => (
                  <li
                    key={r.id}
                    className="flex flex-col gap-1 py-4 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <span className="font-medium text-white">
                      {r.username?.trim() || "User"}
                    </span>
                    <div className="flex flex-wrap items-center gap-4 text-sm">
                      <span className={statusClass(r.subscription_status)}>
                        {statusLabel(r.subscription_status)}
                      </span>
                      <span className="text-gray-400">
                        Joined {formatJoinDate(r.created_at)}
                      </span>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </div>
    </>
  )
}
