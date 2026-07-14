"use client"

import { useEffect, useRef, useState, Suspense } from "react"
import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { useUserProfile } from "@/lib/useUserProfile"
import { profileNeedsOnboarding } from "@/lib/profileOnboardingGate"
import {
  buildCreatorSignupPath,
  clearCreatorFlow,
  CREATOR_ACCESS_INVALID_MESSAGE,
  enterCreatorFlow,
  normalizeCreatorAccessCode,
  redeemCreatorAccessCode,
} from "@/lib/creatorAccess"

type RedeemState = "loading" | "error"

function CreatorRedeemInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { user, profile, loading: authLoading, refreshProfile, setProfile } =
    useUserProfile()
  const [state, setState] = useState<RedeemState>("loading")
  const startedRef = useRef(false)

  const code = normalizeCreatorAccessCode(searchParams.get("code"))

  // Persist the invite code immediately — before auth settles — so a stray
  // navigation to /login cannot drop creator context.
  useEffect(() => {
    if (!code) return
    enterCreatorFlow(code)
  }, [code])

  useEffect(() => {
    if (authLoading) return

    if (!code) {
      setState("error")
      return
    }

    if (!user?.id) {
      router.replace(buildCreatorSignupPath(code))
      return
    }

    // Wait for profile before deciding onboarding vs redeem.
    if (profile == null) return

    // New creators must finish profile onboarding before Pro is granted.
    if (profileNeedsOnboarding(profile)) {
      router.replace("/onboarding")
      return
    }

    // Already entitled — do not POST again.
    if (profile.creator_access === true) {
      clearCreatorFlow()
      router.replace("/dashboard?creator=activated")
      return
    }

    if (startedRef.current) return
    startedRef.current = true

    void (async () => {
      try {
        const result = await redeemCreatorAccessCode(code)
        if (!result.ok) {
          setState("error")
          return
        }

        clearCreatorFlow()
        setProfile((p) =>
          p
            ? {
                ...p,
                ...result.entitlement,
              }
            : p
        )
        void refreshProfile()
        router.replace("/dashboard?creator=activated")
      } catch {
        setState("error")
      }
    })()
  }, [authLoading, user?.id, profile, code, router, refreshProfile, setProfile])

  if (state === "error") {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-950 px-4 text-white">
        <div className="max-w-md rounded-xl border border-white/10 bg-white/5 p-8 text-center backdrop-blur-md">
          <h1 className="text-xl font-semibold text-white">Creator Access</h1>
          <p className="mt-3 text-sm text-gray-300">
            {CREATOR_ACCESS_INVALID_MESSAGE}
          </p>
          <Link
            href="/dashboard"
            className="mt-6 inline-block rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
          >
            Go to Dashboard
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-950 px-4 text-white">
      <div className="max-w-md rounded-xl border border-white/10 bg-white/5 p-8 text-center backdrop-blur-md">
        <h1 className="text-xl font-semibold text-white">Creator Access</h1>
        <p className="mt-3 text-sm text-gray-300">
          {profile == null
            ? "Loading…"
            : profileNeedsOnboarding(profile)
              ? "Continue to profile setup…"
              : "Activating complimentary Pro access…"}
        </p>
      </div>
    </div>
  )
}

export default function CreatorPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-slate-950 text-sm text-gray-300">
          Loading…
        </div>
      }
    >
      <CreatorRedeemInner />
    </Suspense>
  )
}
