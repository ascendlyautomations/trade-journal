'use client'

import { useState, useEffect, useRef } from "react"
import { GoogleSignInButton, FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { supabase } from "@/lib/supabaseClient"
import {
  ensureProfileForUser,
  readStoredReferralCode,
} from "@/lib/ensureProfileForUser"
import { notifyAffiliateReferralAttribution } from "@/lib/notifyAffiliateReferralAttribution"
import { devLog } from "@/lib/devLog"
import { useRouter } from "next/navigation"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import AuthPasswordInput from "@/app/components/ui/AuthPasswordInput"
import { persistReferralCodeFromUrl } from "@/lib/referralPersistence"
import { enterSignupFlow, setCheckoutBillingInterval, setSignupIntent, getSignupIntent, type SignupIntent } from "@/lib/signupFlow"
import SignupPlanPicker from "@/app/components/SignupPlanPicker"
import { markProfileUseFreeTier } from "@/lib/markFreeTierSignup"
import {
  TRAXPRO_DEFAULT_BILLING_INTERVAL,
  type TraxProBillingIntervalId,
} from "@/lib/traxProBillingPlans"
import { useUserProfile } from "@/lib/useUserProfile"
import { prefetchCriticalAppRoutes } from "@/lib/routePrefetch"
import { startTraxProCheckout } from "@/lib/startTraxProCheckout"
import {
  buildCreatorSignupPath,
  enterCreatorFlow,
  getPendingCreatorCode,
  normalizeCreatorAccessCode,
} from "@/lib/creatorAccess"

function getSafeNextPath(): string | null {
  if (typeof window === "undefined") return null
  const raw = new URLSearchParams(window.location.search).get("next")
  if (!raw || raw === "checkout") return null
  try {
    const path = decodeURIComponent(raw)
    if (!path.startsWith("/") || path.startsWith("//")) return null
    return path
  } catch {
    return null
  }
}

export default function LoginPage() {
  const { user, loading: authLoading } = useUserProfile()
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [name, setName] = useState("")
  const [isLogin, setIsLogin] = useState(true)
  const [loading, setLoading] = useState(false)
  const [showReset, setShowReset] = useState(false)
  const [resetEmail, setResetEmail] = useState("")
  const [resetMessage, setResetMessage] = useState("")
  const [loadingReset, setLoadingReset] = useState(false)
  const [googleLoading, setGoogleLoading] = useState(false)
  const [agreedToTerms, setAgreedToTerms] = useState(false)
  const checkoutInFlightRef = useRef(false)
  const [billingInterval, setBillingInterval] = useState<TraxProBillingIntervalId>(
    TRAXPRO_DEFAULT_BILLING_INTERVAL
  )
  const [signupPlanIntent, setSignupPlanIntent] = useState<SignupIntent | null>(
    () => getSignupIntent()
  )
  const { showPopup, feedbackModalProps } = useFeedbackPopup({ autoDismissMs: 3000 })

  const router = useRouter()

  function applySignupPlanIntent(intent: SignupIntent) {
    setSignupPlanIntent(intent)
    setSignupIntent(intent)
    enterSignupFlow()
    if (intent === "trial") {
      setCheckoutBillingInterval(billingInterval)
    }
  }

  function maybePrefetchDashboardBeforeNav(path: string) {
    if (path === "/dashboard" || path.startsWith("/dashboard/")) {
      prefetchCriticalAppRoutes(router)
    }
  }

  function handleBack() {
    router.push("/")
  }

  const shouldStartCheckout = () => {
    if (typeof window === "undefined") return false
    return new URLSearchParams(window.location.search).get("next") === "checkout"
  }

  async function startCheckoutAfterAuth(
    _userId: string,
    interval: TraxProBillingIntervalId = billingInterval
  ) {
    if (checkoutInFlightRef.current) return
    checkoutInFlightRef.current = true

    try {
      const url = await startTraxProCheckout({ billingInterval: interval })
      window.location.href = url
    } finally {
      checkoutInFlightRef.current = false
    }
  }

  useEffect(() => {
    if (typeof window === "undefined") return
    persistReferralCodeFromUrl()
    const params = new URLSearchParams(window.location.search)
    if (params.get("tab") === "signup") {
      setIsLogin(false)
    }
  }, [])

  // Creator invites must never stay on the trial/billing login page.
  useEffect(() => {
    if (authLoading || user?.id) return

    const pending = getPendingCreatorCode()
    if (pending) {
      router.replace(buildCreatorSignupPath(pending))
      return
    }

    const next = getSafeNextPath()
    if (!next?.startsWith("/creator")) return

    try {
      const url = new URL(next, window.location.origin)
      const code = normalizeCreatorAccessCode(url.searchParams.get("code"))
      if (!code) return
      enterCreatorFlow(code)
      router.replace(buildCreatorSignupPath(code))
    } catch {
      /* ignore malformed next */
    }
  }, [authLoading, user?.id, router])

  useEffect(() => {
    if (!shouldStartCheckout() || authLoading) return
    if (!user?.id) return

    let cancelled = false
    void (async () => {
      try {
        setLoading(true)
        await startCheckoutAfterAuth(user.id)
      } catch (e) {
        if (!cancelled) {
          console.error("Checkout continuation failed:", e)
          showPopup({
            type: "error",
            message:
              "Logged in, but checkout failed. Please try again from Pricing.",
          })
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()

    return () => {
      cancelled = true
    }
  }, [user?.id, authLoading, showPopup])

  useEffect(() => {
    if (shouldStartCheckout() || authLoading) return

    const next = getSafeNextPath()
    if (!next || !user?.id) return

    maybePrefetchDashboardBeforeNav(next)
    router.replace(next)
  }, [user?.id, authLoading, router])

  async function handleSignUp(intent: SignupIntent) {
    devLog("Signup clicked", intent)
    if (loading) return

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

    setSignupIntent(intent)
    setSignupPlanIntent(intent)
    if (intent === "trial") {
      enterSignupFlow()
      setCheckoutBillingInterval(billingInterval)
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
        if (/already registered/i.test(authError.message || "")) {
          showPopup({ type: "error", message: handleSupabaseError(authError) })
          return
        }
        console.error(
          "AUTH ERROR:",
          JSON.stringify(
            {
              message: authError.message,
              name: authError.name,
              status: (authError as { status?: number }).status,
            },
            null,
            2
          )
        )
        showPopup({ type: "error", message: handleSupabaseError(authError) })
        return
      }

      const user = data?.user

      devLog("SIGNUP USER:", user)

      if (!user) {
        showPopup({
          type: "info",
          message: "Check your email to confirm your account before continuing.",
        })
        return
      }

      const ensureResult = await ensureProfileForUser(supabase, {
        userId: user.id,
        name: name?.trim() || null,
        referredBy: referralCode,
        userMetadata: user.user_metadata,
      })

      if (!ensureResult.ok) {
        console.error("PROFILE ENSURE ERROR:", ensureResult.error)
        showPopup({ type: "error", message: "Error creating profile" })
        return
      }

      devLog("✅ PROFILE ENSURED")

      if (ensureResult.created && referralCode?.trim()) {
        notifyAffiliateReferralAttribution()
      }

      if (intent === "free") {
        const freeResult = await markProfileUseFreeTier(supabase, user.id)
        if (!freeResult.ok) {
          console.error("Failed to mark free tier at signup:", freeResult.error)
        }
      }

      if (shouldStartCheckout()) {
        try {
          await startCheckoutAfterAuth(user.id)
          return
        } catch (e) {
          console.error("Checkout after signup failed:", e)
          showPopup({
            type: "error",
            message: "Signed up, but checkout failed. Please try again from Pricing.",
          })
        }
      }

      router.push(getSafeNextPath() ?? "/onboarding")
    } catch (err) {
      console.error(
        "ERROR:",
        JSON.stringify(
          err instanceof Error
            ? { message: err.message, name: err.name }
            : err,
          null,
          2
        )
      )
      showPopup({ type: "error", message: "Something went wrong during signup" })
    } finally {
      setLoading(false)
    }
  }

  const handleLogin = async () => {
    devLog("Login clicked")
    if (loading) return
    setLoading(true)

    const { data: signInData, error } = await supabase.auth.signInWithPassword({
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

    if (shouldStartCheckout() && signInData.user) {
      try {
        await startCheckoutAfterAuth(signInData.user.id)
        setLoading(false)
        return
      } catch (e) {
        console.error("Checkout after login failed:", e)
        showPopup({
          type: "error",
          message: "Logged in, but checkout failed. Please try again from Pricing.",
        })
        setLoading(false)
        return
      }
    }

    const dest = getSafeNextPath() ?? "/dashboard"
    maybePrefetchDashboardBeforeNav(dest)
    router.push(dest)
    setLoading(false)
  }

  const handleGoogleLogin = async () => {
    if (googleLoading || loading) return

    if (!isLogin && !agreedToTerms) {
      showPopup({
        type: "error",
        message:
          "You must agree to the Terms of Service and Privacy Policy before creating an account.",
      })
      return
    }

    if (!isLogin) {
      const intent = signupPlanIntent ?? getSignupIntent()
      if (!intent) {
        showPopup({
          type: "error",
          message:
            "Choose Start Free Trial or Continue Free below before signing up with Google.",
        })
        return
      }
      applySignupPlanIntent(intent)
    }

    setGoogleLoading(true)

    try {
    if (!isLogin) {
      enterSignupFlow()
    }
    let redirectPath = isLogin ? "/dashboard" : "/onboarding"
    if (shouldStartCheckout()) {
      redirectPath = "/login?next=checkout"
    } else {
      const next = getSafeNextPath()
      if (next) redirectPath = next
    }
    await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${location.origin}${redirectPath}`,
      },
    })
    } finally {
      setGoogleLoading(false)
    }
  }

  const handleReset = async () => {
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

  return (
  <div className="relative flex min-h-screen items-center justify-center text-white">

    {/* 🔥 FULL BACKGROUND IMAGE */}
    <img
      src="/tradetrax-bg.webp"
      alt="bg"
      className="absolute inset-0 w-full h-full object-cover"
    />

    {/* 🔥 DARK OVERLAY (IMPORTANT FOR READABILITY) */}
    <div className="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>

    <button
      type="button"
      onClick={handleBack}
      className="absolute left-3 top-3 z-20 inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/10 bg-white/10 text-base leading-none text-gray-200 backdrop-blur-md transition hover:bg-white/15 hover:text-white md:left-6 md:top-6 md:h-auto md:min-h-[44px] md:w-auto md:gap-2 md:px-4 md:py-2 md:text-sm md:font-medium"
      aria-label="Go home"
    >
      <span aria-hidden="true">←</span>
      <span className="hidden md:inline">Home</span>
    </button>

    {/* 🔥 CONTENT */}
    <div className="relative z-10 flex w-full max-w-6xl flex-col items-center justify-between px-6 md:flex-row">

      {/* LEFT TEXT */}
      <div className="mb-10 max-w-lg text-center max-md:pt-3 md:mb-0 md:text-left">
        <p className="text-sm tracking-widest text-blue-300 mb-5">
          WELCOME TO
        </p>

        <h1 className="text-5xl font-bold mb-4 text-blue-300">
          TradeTraxs
        </h1>

        <p className="text-lg text-gray-300">
          Track. Analyze. Socialize. Dominate your trading.
        </p>
      </div>

      {/* RIGHT LOGIN CARD */}
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-white/10 p-8 shadow-2xl backdrop-blur-xl md:py-6 md:px-8">

        {/* Toggle */}
        <div
          className="mb-6 flex rounded-xl bg-white/10 p-1 md:mb-4"
          role="tablist"
          aria-label="Login or sign up"
        >
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
            Login
          </button>
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
          onClick={handleGoogleLogin}
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
            if (isLogin) handleLogin()
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
            className="w-full rounded-xl border border-white/10 bg-white/10 px-4 py-3 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400 md:py-2.5"
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

          {isLogin ? (
            <button
              type="submit"
              disabled={loading}
              className="w-full rounded-xl bg-blue-500 py-3 font-semibold transition hover:bg-blue-600 hover:scale-105 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500 disabled:hover:scale-100 md:py-2.5"
            >
              {loading ? "Loading..." : "Login"}
            </button>
          ) : null}
        </form>

        {!isLogin ? (
          <div className="mt-6 md:mt-4">
            <div className="relative mb-6 md:mb-4">
              <div className="absolute inset-0 flex items-center" aria-hidden>
                <div className="w-full border-t border-white/10" />
              </div>
              <p className="relative mx-auto w-fit bg-transparent px-3 text-center text-xs text-gray-400">
                Choose how you&apos;d like to get started
              </p>
            </div>

            <div className="space-y-3 md:space-y-2.5">
              <SignupPlanPicker
                billingInterval={billingInterval}
                onBillingIntervalChange={(interval) => {
                  setBillingInterval(interval)
                  setCheckoutBillingInterval(interval)
                }}
                selectedIntent={signupPlanIntent}
                onSelectIntent={applySignupPlanIntent}
                onSelectTrial={() => void handleSignUp("trial")}
                onSelectFree={() => void handleSignUp("free")}
                disabled={!agreedToTerms}
                loading={loading}
                billingPickerName="login-signup-billing"
              />
            </div>
          </div>
        ) : null}

        {isLogin && showReset && (
          <div className="mt-4 rounded-lg border border-white/10 bg-white/5 p-4">
            <p className="mb-2 text-sm">Enter your email to reset your password</p>

            <input
              type="email"
              placeholder="Email"
              value={resetEmail}
              onChange={(e) => setResetEmail(e.target.value)}
              className="w-full rounded bg-black/30 border border-white/10 p-2"
            />

            <button
              type="button"
              onClick={handleReset}
              disabled={loadingReset}
              className="mt-2 w-full bg-blue-500 hover:bg-blue-600 text-white py-2 rounded disabled:opacity-50"
            >
              {loadingReset ? "Sending..." : "Send Reset Link"}
            </button>

            {resetMessage && <p className="mt-2 text-xs text-gray-400">{resetMessage}</p>}
          </div>
        )}

        <p className="mt-6 text-center text-xs text-gray-500 md:mt-4">
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
      </div>
    </div>
    <FeedbackModal {...feedbackModalProps} />
  </div>
)
}