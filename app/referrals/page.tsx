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
import EmptyState from "@/app/components/ui/EmptyState"
import { SkeletonReferralsPage } from "@/app/components/ui/skeletons"
import { LOADING_COPY } from "@/lib/loadingCopy"
import { useUserProfile } from "@/lib/useUserProfile"
import { fetchSettingsProfileRow } from "@/lib/settingsProfileSync"
import { readSettingsProfileCache } from "@/lib/settingsProfileCache"

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
  const { user, profile: contextProfile } = useUserProfile()
  const [loading, setLoading] = useState(true)
  const [profile, setProfile] = useState<ProfileRow | null>(null)
  const [referrals, setReferrals] = useState<ReferredProfile[]>([])
  const [ledgerTotal, setLedgerTotal] = useState(0)
  const [copyDone, setCopyDone] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)

    if (!user) {
      setLoading(false)
      router.push("/login")
      return
    }

    const cachedProfile =
      readSettingsProfileCache(user.id) ??
      (await fetchSettingsProfileRow(supabase, user.id).catch(() => null))

    if (!cachedProfile) {
      setProfile(null)
      setReferrals([])
      setLedgerTotal(0)
      setLoading(false)
      return
    }

    const mergedProfile: ProfileRow = {
      id: user.id,
      referral_code: contextProfile?.referral_code ?? null,
    }
    setProfile(mergedProfile)

    const { data: ledger, error: ledgerErr } = await supabase
      .from("referrals")
      .select("amount_earned")
      .eq("referrer_user_id", user.id)

    if (ledgerErr) {
      console.error("referrals ledger:", ledgerErr)
      setLedgerTotal(recordedAffiliateEarnings(cachedProfile.referral_earnings as number | null))
    } else {
      setLedgerTotal(
        resolveRecordedAffiliateEarnings(
          cachedProfile.referral_earnings as number | null | undefined,
          ledger
        )
      )
    }

    const code =
      contextProfile?.referral_code != null
        ? String(contextProfile.referral_code).trim()
        : ""
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
  }, [router, user, contextProfile?.referral_code])

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
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 text-white sm:px-6 lg:px-8">
        <div className="mx-auto max-w-5xl">
          <div className="mb-8">
            <h1 className="text-2xl font-bold text-blue-300 sm:text-3xl">
              Referral stats
            </h1>
            <p className="mt-2 text-sm text-gray-400">{LOADING_COPY.referrals}</p>
          </div>
          <SkeletonReferralsPage />
        </div>
      </div>
    )
  }

  return (
    <>

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 text-white sm:px-6 lg:px-8">
        <div className="mx-auto max-w-5xl">
          <div className="mb-8 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h1 className="text-2xl font-bold text-blue-300 sm:text-3xl">
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
                  className="shrink-0 rounded-xl bg-blue-500 px-5 py-2.5 text-sm font-semibold text-white hover:bg-blue-600 disabled:hover:bg-blue-500"
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
              <EmptyState
                icon="🔗"
                title="No referrals yet"
                description="Share your link to start earning when traders join TradeTraxs."
                action={
                  referralCode ? (
                    <button
                      type="button"
                      onClick={() => void copyLink()}
                      className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:hover:bg-blue-500"
                    >
                      {copyDone ? "Copied!" : "Copy referral link"}
                    </button>
                  ) : undefined
                }
                className="mt-6 border-0 bg-transparent py-6"
              />
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
