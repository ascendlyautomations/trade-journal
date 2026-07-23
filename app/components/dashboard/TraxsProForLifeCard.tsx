"use client"

import { useEffect, useMemo, useRef, useState } from "react"
import {
  buildEarlyAccessReferralLink,
  earlyAccessDaysRemaining,
  type ProForLifeClaimResult,
} from "@/lib/earlyAccess"
import { claimCurrentUserProForLife } from "@/lib/earlyAccessClient"
import { useEarlyAccessChallengeProgress } from "@/lib/useEarlyAccessChallengeProgress"
import { useToast } from "@/app/components/ui"
import { shareUrl } from "@/lib/shareService"

type TraxsProForLifeCardProps = {
  referralCode: string | null | undefined
  onAwarded: () => void | Promise<void>
}

function ProgressRow({
  label,
  current,
  target,
}: {
  label: string
  current: number
  target: number
}) {
  const complete = current >= target
  return (
    <li className="flex min-h-[48px] items-center justify-between gap-4 py-2.5 text-sm">
      <span
        className={`flex min-w-0 flex-1 items-center gap-2.5 ${
          complete ? "text-gray-300" : "text-white"
        }`}
      >
        <span
          className={`inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-xs ${
            complete
              ? "bg-emerald-500/20 text-emerald-300"
              : "bg-white/10 text-gray-400"
          }`}
          aria-hidden
        >
          {complete ? "✓" : "·"}
        </span>
        <span className="min-w-0 flex-1">{label}</span>
      </span>
      <span className="shrink-0 font-medium tabular-nums text-gray-300">
        {Math.min(current, target)} / {target}
      </span>
    </li>
  )
}

export default function TraxsProForLifeCard({
  referralCode,
  onAwarded,
}: TraxsProForLifeCardProps) {
  const toast = useToast()
  const { progress, loaded, refresh } = useEarlyAccessChallengeProgress(true)
  const loading = !loaded
  const [claiming, setClaiming] = useState(false)
  const [claimResult, setClaimResult] =
    useState<ProForLifeClaimResult | null>(null)
  const claimAttemptedRef = useRef(false)
  const referralLink = useMemo(
    () => buildEarlyAccessReferralLink(referralCode),
    [referralCode]
  )

  useEffect(() => {
    void refresh()
    const interval = window.setInterval(() => void refresh(), 30_000)
    const onFocus = () => void refresh()
    window.addEventListener("focus", onFocus)
    return () => {
      window.clearInterval(interval)
      window.removeEventListener("focus", onFocus)
    }
  }, [refresh])

  useEffect(() => {
    if (
      !progress?.allComplete ||
      progress.status !== "active" ||
      progress.alreadyAwarded ||
      claimAttemptedRef.current
    ) {
      return
    }

    claimAttemptedRef.current = true
    setClaiming(true)
    void claimCurrentUserProForLife()
      .then(async (result) => {
        setClaimResult(result.result)
        if (
          result.result === "awarded" ||
          result.result === "already_awarded"
        ) {
          toast.success("Traxs Pro For Life unlocked.")
          await onAwarded()
          return
        }
        if (result.result === "sold_out") {
          toast.info("The founding Pro For Life allocation is full.")
        }
        await refresh()
      })
      .catch((error) => {
        console.error("[TraxsProForLifeCard] claim:", error)
        claimAttemptedRef.current = false
        toast.error("Could not verify your Pro For Life claim. Try again.")
      })
      .finally(() => setClaiming(false))
  }, [onAwarded, progress, refresh, toast])

  if (loading) {
    return (
      <section className="h-48 animate-pulse rounded-xl border border-white/10 bg-white/5" />
    )
  }

  if (
    !progress ||
    !progress.status ||
    progress.status === "ineligible" ||
    progress.status === "converted_lifetime" ||
    progress.alreadyAwarded
  ) {
    return null
  }

  const daysRemaining = earlyAccessDaysRemaining(progress.endsAt)
  const soldOut =
    claimResult === "sold_out" ||
    (progress.spotsRemaining <= 0 && !progress.alreadyAwarded)
  const expired = progress.status === "expired" || daysRemaining <= 0
  const expirationLabel = progress.endsAt
    ? new Date(progress.endsAt).toLocaleString(undefined, {
        month: "long",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
      })
    : "Unavailable"

  async function copyReferralLink() {
    if (!referralLink) return
    try {
      await navigator.clipboard.writeText(referralLink)
      toast.success("Referral link copied.")
    } catch {
      toast.error("Could not copy the referral link.")
    }
  }

  async function shareReferralLink() {
    if (!referralLink) return
    try {
      const result = await shareUrl({
        title: "Join me on TradeTraxs",
        text: "Create your TradeTraxs account using my referral link.",
        url: referralLink,
      })
      // Web without Web Share API: fall back to clipboard (prior behavior).
      if (!result.ok && !result.cancelled) {
        await copyReferralLink()
      }
    } catch {
      toast.error("Could not open sharing.")
    }
  }

  return (
    <section className="rounded-xl border border-amber-300/25 bg-amber-300/[0.07] p-4 backdrop-blur-md sm:p-5">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <p className="whitespace-nowrap text-xs font-semibold uppercase tracking-[0.18em] text-amber-200">
            Founding Challenge
          </p>
          <h2 className="mt-1 whitespace-nowrap text-xl font-semibold text-white">
            Traxs Pro For Life
          </h2>
        </div>
        <div className="w-fit shrink-0 rounded-lg border border-white/10 bg-black/20 px-3 py-2 text-sm sm:text-right">
          <p className="whitespace-nowrap font-semibold text-white">
            {expired ? "Expired" : `${daysRemaining} days remaining`}
          </p>
          <p className="mt-0.5 text-xs text-gray-400">{expirationLabel}</p>
        </div>
      </div>
      <p className="mt-2 max-w-2xl text-sm leading-relaxed text-gray-300">
        Complete all three challenges before your complimentary Pro access
        expires to permanently unlock Traxs Pro. Awards are limited to the
        first qualifying users.
      </p>

      {soldOut ? (
        <div className="mt-4 rounded-lg border border-amber-300/30 bg-amber-300/10 p-3 text-sm text-amber-100">
          The founding Pro For Life allocation is full. Your complimentary Pro
          remains available until its listed expiration time.
        </div>
      ) : expired ? (
        <div className="mt-4 rounded-lg border border-red-400/25 bg-red-500/10 p-3 text-sm text-red-100">
          Your complimentary Pro period has ended. The normal subscription
          options are available when you continue using Pro features.
        </div>
      ) : null}

      <ul className="mt-4 divide-y divide-white/10 rounded-lg border border-white/10 bg-black/15 px-3">
        <ProgressRow
          label="Follow 3 traders"
          current={progress.followCount}
          target={3}
        />
        <ProgressRow
          label="Post a public trade on 3 different days"
          current={progress.publicTradeDayCount}
          target={3}
        />
        <ProgressRow
          label="Refer one trader who creates an account"
          current={progress.referralCount}
          target={1}
        />
      </ul>

      <div className="mt-4 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <p className="text-sm font-medium text-white">
          Overall progress: {progress.completedCount} / 3 complete
        </p>
        {!soldOut ? (
          <p className="text-xs text-gray-400">
            {progress.spotsRemaining} of {progress.awardLimit} founding spots
            currently remain.
          </p>
        ) : null}
      </div>

      <div className="mt-3 flex flex-col gap-2 sm:max-w-md sm:flex-row">
        <button
          type="button"
          disabled={!referralLink}
          onClick={() => void copyReferralLink()}
          className="w-full whitespace-nowrap rounded-lg border border-white/15 bg-white/10 px-3 py-2 text-sm font-medium text-white hover:bg-white/15 disabled:opacity-50 sm:flex-1"
        >
          Copy Referral Link
        </button>
        <button
          type="button"
          disabled={!referralLink}
          onClick={() => void shareReferralLink()}
          className="w-full whitespace-nowrap rounded-lg bg-blue-600 px-3 py-2 text-sm font-medium text-white hover:bg-blue-500 disabled:opacity-50 sm:flex-1"
        >
          Share Referral Link
        </button>
      </div>

      {claiming ? (
        <p className="mt-3 text-xs text-amber-100">
          Verifying your completed challenges and available founding spot…
        </p>
      ) : null}
    </section>
  )
}
