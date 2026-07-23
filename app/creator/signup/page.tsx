"use client"

import { Suspense, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { GoogleSignInButton, FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import AuthPasswordInput from "@/app/components/ui/AuthPasswordInput"
import { supabase } from "@/lib/supabaseClient"
import {
  clearStoredReferralCode,
  ensureProfileForUser,
  readStoredReferralCode,
} from "@/lib/ensureProfileForUser"
import { notifyAffiliateReferralAttribution } from "@/lib/notifyAffiliateReferralAttribution"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { useUserProfile } from "@/lib/useUserProfile"
import { prefetchCriticalAppRoutes } from "@/lib/routePrefetch"
import {
  buildCreatorRedeemPath,
  enterCreatorFlow,
  normalizeCreatorAccessCode,
} from "@/lib/creatorAccess"
import { isNativeIos } from "@/lib/nativePlatform"
import { startNativeIosGoogleOAuth } from "@/lib/nativeIosOAuth"

function CreatorSignupInner() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { user, loading: authLoading } = useUserProfile()
  const { showPopup, feedbackModalProps } = useFeedbackPopup({ autoDismissMs: 3000 })

  const code = normalizeCreatorAccessCode(searchParams.get("code"))
  const redeemPath = code ? buildCreatorRedeemPath(code) : null

  const [isLogin, setIsLogin] = useState(false)
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [name, setName] = useState("")
  const [agreedToTerms, setAgreedToTerms] = useState(false)
  const [loading, setLoading] = useState(false)
  const [googleLoading, setGoogleLoading] = useState(false)
  const [showReset, setShowReset] = useState(false)
  const [resetEmail, setResetEmail] = useState("")
  const [resetMessage, setResetMessage] = useState("")
  const [loadingReset, setLoadingReset] = useState(false)

  useEffect(() => {
    if (!code) {
      router.replace("/")
      return
    }
    enterCreatorFlow(code)
    if (authLoading) return
    if (!user?.id) return
    prefetchCriticalAppRoutes(router)
    router.replace(redeemPath!)
  }, [authLoading, user?.id, code, redeemPath, router])

  function handleBack() {
    router.push("/")
  }

  async function handleSignUp() {
    if (loading || !redeemPath) return

    if (!agreedToTerms) {
      showPopup({
        type: "error",
        message:
          "You must agree to the Terms of Service and Privacy Policy before creating an account.",
      })
      return
    }

    if (!email.trim() || !password) {
      showPopup({
        type: "error",
        message: "Please enter your email and password.",
      })
      return
    }

    setLoading(true)
    try {
      const referralCode = readStoredReferralCode()

      const { data, error: authError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            name: name?.trim() || null,
            referral_code: referralCode || null,
          },
        },
      })

      if (authError) {
        showPopup({ type: "error", message: handleSupabaseError(authError) })
        return
      }

      const signedUpUser = data?.user
      if (!signedUpUser) {
        showPopup({
          type: "info",
          message: "Check your email to confirm your account before continuing.",
        })
        return
      }

      const ensureResult = await ensureProfileForUser(supabase, {
        userId: signedUpUser.id,
        name: name?.trim() || null,
        referredBy: referralCode,
        userMetadata: signedUpUser.user_metadata,
        signupFlowSource: "creator",
      })

      if (!ensureResult.ok) {
        console.error("PROFILE ENSURE ERROR:", ensureResult.error)
        showPopup({ type: "error", message: "Error creating profile" })
        return
      }

      if (ensureResult.created && referralCode?.trim()) {
        notifyAffiliateReferralAttribution()
      }

      // Referral is in auth metadata (and possibly the profile). Clear browser
      // state so it cannot attribute a future account on this device.
      if (referralCode?.trim()) {
        clearStoredReferralCode()
      }

      prefetchCriticalAppRoutes(router)
      // Skip /creator hop — go straight to profile setup. Code stays in sessionStorage.
      router.replace("/onboarding")
    } catch (err) {
      console.error("Creator signup error:", err)
      showPopup({ type: "error", message: "Something went wrong during signup" })
    } finally {
      setLoading(false)
    }
  }

  async function handleLogin() {
    if (loading || !redeemPath) return
    setLoading(true)

    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (error) {
      showPopup({ type: "error", message: "Incorrect email or password" })
      setEmail("")
      setPassword("")
      setLoading(false)
      return
    }

    prefetchCriticalAppRoutes(router)
    router.push(redeemPath)
    setLoading(false)
  }

  async function handleGoogleLogin() {
    if (googleLoading || loading || !redeemPath) return

    if (!isLogin && !agreedToTerms) {
      showPopup({
        type: "error",
        message:
          "You must agree to the Terms of Service and Privacy Policy before creating an account.",
      })
      return
    }

    setGoogleLoading(true)
    try {
      if (!redeemPath) return

      // Capacitor iOS: in-app browser + custom-scheme callback.
      // Web keeps the existing origin redirect flow unchanged.
      if (isNativeIos()) {
        await startNativeIosGoogleOAuth(redeemPath)
        return
      }

      await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          redirectTo: `${location.origin}${redeemPath}`,
        },
      })
    } finally {
      setGoogleLoading(false)
    }
  }

  async function handleReset() {
    if (!resetEmail || loadingReset) return

    setLoadingReset(true)
    const { error } = await supabase.auth.resetPasswordForEmail(resetEmail, {
      redirectTo: `${window.location.origin}/reset-password`,
    })

    if (error) {
      console.error("Reset error:", error)
      setResetMessage("Error sending reset email")
      showPopup({ type: "error", message: "Error sending reset email" })
    } else {
      setResetMessage("Check your email for instructions to reset your password")
      showPopup({
        type: "success",
        message: "Check your email for instructions to reset your password",
      })
      setResetEmail("")
    }
    setLoadingReset(false)
  }

  if (!code) {
    return null
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center text-white">
      <img
        src="/tradetrax-bg.webp"
        alt="bg"
        className="absolute inset-0 h-full w-full object-cover"
      />
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" />

      <button
        type="button"
        onClick={handleBack}
        className="absolute left-3 top-3 z-20 inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/10 bg-white/10 text-base leading-none text-gray-200 backdrop-blur-md transition hover:bg-white/15 hover:text-white md:left-6 md:top-6 md:h-auto md:min-h-[44px] md:w-auto md:gap-2 md:px-4 md:py-2 md:text-sm md:font-medium"
        aria-label="Go home"
      >
        <span aria-hidden="true">←</span>
        <span className="hidden md:inline">Home</span>
      </button>

      <div className="relative z-10 flex w-full max-w-6xl flex-col items-center justify-between px-6 md:flex-row">
        <div className="mb-10 max-w-lg text-center max-md:pt-3 md:mb-0 md:text-left">
          <h1 className="mb-4 text-3xl font-bold leading-tight text-blue-300 sm:text-4xl md:text-[2.5rem]">
            Welcome to TradeTraxs Creator Access
          </h1>
          <div className="space-y-3 text-base leading-relaxed text-gray-300">
            <p>
              You&apos;ve been invited to explore TradeTraxs with complimentary Pro
              access.
            </p>
            <p>
              Create your account below and we&apos;ll automatically activate your
              Creator Access after you sign up.
            </p>
          </div>
        </div>

        <div className="w-full max-w-md rounded-2xl border border-white/10 bg-white/10 p-8 shadow-2xl backdrop-blur-xl md:px-8 md:py-6">
          <div
            className="mb-6 flex rounded-xl bg-white/10 p-1 md:mb-4"
            role="tablist"
            aria-label="Sign up or log in"
          >
            <button
              type="button"
              onClick={() => {
                setIsLogin(false)
              }}
              className={`flex-1 rounded-lg py-2 font-semibold transition md:py-1.5 ${
                !isLogin ? "bg-white text-black" : "text-white"
              }`}
            >
              Sign Up
            </button>
            <button
              type="button"
              onClick={() => {
                setIsLogin(true)
                setAgreedToTerms(false)
              }}
              className={`flex-1 rounded-lg py-2 font-semibold transition md:py-1.5 ${
                isLogin ? "bg-white text-black" : "text-white"
              }`}
            >
              Log In
            </button>
          </div>

          <h2 className="mb-6 text-center text-xl font-semibold md:mb-4">
            {isLogin ? "Sign in to continue" : "Create your account"}
          </h2>

          {!isLogin && (
            <label className="mb-5 flex cursor-pointer items-start gap-3 text-left text-sm leading-snug text-gray-300 md:mb-3">
              <input
                type="checkbox"
                checked={agreedToTerms}
                onChange={(e) => setAgreedToTerms(e.target.checked)}
                className="mt-0.5 h-4 w-4 shrink-0 rounded border-white/20 bg-white/10 text-blue-500 focus:ring-2 focus:ring-blue-400 focus:ring-offset-0"
              />
              <span>
                I agree to the{" "}
                <a
                  href="/terms"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 underline underline-offset-2 hover:text-blue-300"
                  onClick={(e) => e.stopPropagation()}
                >
                  Terms of Service
                </a>{" "}
                and{" "}
                <a
                  href="/privacy"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 underline underline-offset-2 hover:text-blue-300"
                  onClick={(e) => e.stopPropagation()}
                >
                  Privacy Policy
                </a>
                .
              </span>
            </label>
          )}

          <GoogleSignInButton
            label={isLogin ? "sign-in" : "sign-up"}
            onClick={() => void handleGoogleLogin()}
            disabled={loading || (!isLogin && !agreedToTerms)}
            loading={googleLoading}
            className="mb-4 md:mb-3"
          />

          <div className="mb-4 text-center text-sm text-gray-400 md:mb-3">or</div>

          {!isLogin && (
            <input
              type="text"
              placeholder="Full Name"
              className="mb-4 w-full rounded-xl border border-white/10 bg-white/10 px-4 py-3 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400 md:mb-3 md:py-2.5"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          )}

          <form
            className="flex flex-col gap-3 md:gap-2.5"
            onSubmit={(e) => {
              e.preventDefault()
              if (isLogin) void handleLogin()
              else void handleSignUp()
            }}
          >
            <input
              type="email"
              placeholder="Email"
              autoComplete="email"
              className="w-full rounded-xl border border-white/10 bg-white/10 px-4 py-3 text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400 md:py-2.5"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />

            <AuthPasswordInput
              placeholder="Password"
              autoComplete={isLogin ? "current-password" : "new-password"}
              className="w-full rounded-xl border border-white/10 bg-white/10 px-4 py-3 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400 md:py-2.5"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />

            {isLogin && (
              <button
                type="button"
                onClick={() => setShowReset(!showReset)}
                className="self-start p-0 text-sm text-blue-400 hover:underline"
              >
                Forgot password?
              </button>
            )}

            <button
              type="submit"
              disabled={loading || (!isLogin && !agreedToTerms)}
              className="w-full rounded-xl bg-blue-500 py-3 font-semibold transition hover:scale-105 hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:scale-100 disabled:hover:bg-blue-500 md:py-2.5"
            >
              {loading
                ? "Loading..."
                : isLogin
                  ? "Log In"
                  : "Create Account"}
            </button>
          </form>

          {isLogin && showReset && (
            <div className="mt-4 rounded-lg border border-white/10 bg-white/5 p-4">
              <p className="mb-2 text-sm">
                Enter your email to reset your password
              </p>

              <input
                type="email"
                placeholder="Email"
                value={resetEmail}
                onChange={(e) => setResetEmail(e.target.value)}
                className="w-full rounded border border-white/10 bg-black/30 p-2"
              />

              <button
                type="button"
                onClick={() => void handleReset()}
                disabled={loadingReset}
                className="mt-2 w-full rounded bg-blue-500 py-2 text-white hover:bg-blue-600 disabled:opacity-50"
              >
                {loadingReset ? "Sending..." : "Send Reset Link"}
              </button>

              {resetMessage ? (
                <p className="mt-2 text-xs text-gray-400">{resetMessage}</p>
              ) : null}
            </div>
          )}

          <p className="mt-6 text-center text-xs text-gray-400 md:mt-4">
            <a
              href="/privacy"
              className="text-gray-400 transition hover:text-gray-300 hover:underline"
            >
              Privacy Policy
            </a>
            {" · "}
            <a
              href="/terms"
              className="text-gray-400 transition hover:text-gray-300 hover:underline"
            >
              Terms of Service
            </a>
          </p>

          <p className="mt-3 text-center text-xs text-gray-400">
            Invite code:{" "}
            <span className="font-medium text-gray-400">{code}</span>
          </p>
        </div>
      </div>
      <FeedbackModal {...feedbackModalProps} />
    </div>
  )
}

export default function CreatorSignupPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-slate-950 text-sm text-gray-300">
          Loading…
        </div>
      }
    >
      <CreatorSignupInner />
    </Suspense>
  )
}
