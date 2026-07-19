"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import {
  enrollCurrentUserEarlyAccess,
  fetchCurrentEarlyAccessProgress,
} from "@/lib/earlyAccessClient"
import { EARLY_ACCESS_DURATION_DAYS } from "@/lib/earlyAccess"
import {
  clearEarlyAccessOAuthSignupPending,
  hasEarlyAccessOAuthSignupPending,
} from "@/lib/earlyAccess"
import { ensureProfileForUser, readStoredReferralCode } from "@/lib/ensureProfileForUser"
import { supabase } from "@/lib/supabaseClient"
import { setSignupIntent } from "@/lib/signupFlow"
import { useUserProfile } from "@/lib/useUserProfile"

export default function EarlyAccessWelcomePage() {
  const router = useRouter()
  const { user, profile, loading, refreshProfile } = useUserProfile()
  const [ready, setReady] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (loading) return
    if (!user) {
      router.replace("/login?tab=signup")
      return
    }

    let cancelled = false
    void (async () => {
      try {
        const oauthSignupPending = hasEarlyAccessOAuthSignupPending()
        const authProvider = String(
          user.app_metadata?.provider ?? ""
        ).toLowerCase()
        const source =
          oauthSignupPending ||
          (authProvider !== "" && authProvider !== "email")
            ? "standard_oauth"
            : "standard_email"

        await ensureProfileForUser(supabase, {
          userId: user.id,
          name: null,
          referredBy: readStoredReferralCode(),
          userMetadata: user.user_metadata,
          signupFlowSource: source,
        })

        let enrollment = await enrollCurrentUserEarlyAccess(source)
        if (enrollment === "ineligible") {
          enrollment = await enrollCurrentUserEarlyAccess(source)
        }
        if (oauthSignupPending) {
          clearEarlyAccessOAuthSignupPending()
        }

        if (
          enrollment !== "enrolled" &&
          enrollment !== "already_enrolled"
        ) {
          console.error("[early-access/welcome] enrollment failed", enrollment)
          if (!cancelled) {
            setError(
              "Early Access enrollment did not complete. Please try again."
            )
          }
          return
        }

        setSignupIntent("trial")
        await refreshProfile()
        const progress = await fetchCurrentEarlyAccessProgress()
        if (cancelled) return
        if (progress?.status === "active") {
          setReady(true)
          return
        }
        console.error("[early-access/welcome] progress not active", progress)
        setError(
          "Early Access is not active on this account yet. Please try again."
        )
      } catch (err) {
        console.error("[early-access/welcome]", err)
        if (!cancelled) {
          setError(
            "Early Access enrollment is temporarily unavailable. Please try again."
          )
        }
      }
    })()

    return () => {
      cancelled = true
    }
  }, [loading, refreshProfile, router, user])

  if (error) {
    return (
      <main className="flex min-h-screen flex-col items-center justify-center gap-4 px-4 text-center text-sm text-gray-300">
        <p>{error}</p>
        <button
          type="button"
          onClick={() => window.location.reload()}
          className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-500"
        >
          Retry enrollment
        </button>
      </main>
    )
  }

  if (!ready) {
    return (
      <main className="flex min-h-screen items-center justify-center px-4 text-sm text-gray-300">
        Preparing your account…
      </main>
    )
  }

  return (
    <main className="relative flex min-h-screen items-center justify-center px-4 py-10 text-white">
      <img
        src="/tradetrax-bg.webp"
        alt=""
        className="absolute inset-0 h-full w-full object-cover"
        aria-hidden
      />
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" aria-hidden />

      <section className="relative z-10 w-full max-w-xl rounded-2xl border border-white/10 bg-[#0f172a]/95 p-6 text-center sm:p-8">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-blue-300">
          Complimentary Pro · {EARLY_ACCESS_DURATION_DAYS} Days
        </p>
        <h1 className="mt-3 text-2xl font-semibold text-white sm:text-3xl">
          Welcome to TradeTraxs Early Access
        </h1>
        <div className="mx-auto mt-4 max-w-lg space-y-3 text-sm leading-relaxed text-gray-300 sm:text-base">
          <p>
            Thank you for joining TradeTraxs at an early stage. Your account
            includes {EARLY_ACCESS_DURATION_DAYS} days of complimentary Pro
            access. No credit card is required.
          </p>
          <p>
            After completing your existing profile onboarding, you can take part
            in the Traxs Pro For Life challenge. Follow three traders, share
            public trades on three different days, and invite one friend who
            creates an account for the opportunity to permanently unlock Pro.
          </p>
          <p>
            Lifetime availability is limited to the first qualifying users. Your
            early participation will help shape the future of TradeTraxs.
          </p>
        </div>
        <button
          type="button"
          onClick={() => {
            const destination =
              profile?.onboarding_completed === true
                ? "/dashboard"
                : "/onboarding"
            router.push(destination)
          }}
          className="mt-7 w-full rounded-lg bg-blue-600 px-5 py-3 text-sm font-semibold text-white transition hover:bg-blue-500 sm:w-auto"
        >
          {profile?.onboarding_completed === true
            ? "Continue to Dashboard"
            : "Continue to Profile Setup"}
        </button>
      </section>
    </main>
  )
}
