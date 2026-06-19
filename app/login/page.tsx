'use client'

import { useState, useEffect, useRef } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  ensureProfileForUser,
  readStoredReferralCode,
} from "@/lib/ensureProfileForUser"
import { useRouter } from "next/navigation"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import AuthPasswordInput from "@/app/components/ui/AuthPasswordInput"
import { isBetaReferralRef } from "@/lib/betaReferralCode"
import { notifyAdminBetaSignup } from "@/lib/notifyAdminBetaSignup"
import { persistReferralCodeFromUrl } from "@/lib/referralPersistence"

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
  const [isBetaSignup, setIsBetaSignup] = useState(false)
  const [betaWelcomeExpanded, setBetaWelcomeExpanded] = useState(false)
  const { showPopup, feedbackModalProps } = useFeedbackPopup({ autoDismissMs: 3000 })

  const router = useRouter()

  function handleBack() {
    if (typeof window !== "undefined" && window.history.length > 1) {
      router.back()
    } else {
      router.push("/")
    }
  }

  const shouldStartCheckout = () => {
    if (typeof window === "undefined") return false
    return new URLSearchParams(window.location.search).get("next") === "checkout"
  }

  async function startCheckoutAfterAuth(userId: string) {
    if (checkoutInFlightRef.current) return
    checkoutInFlightRef.current = true

    try {
    const {
      data: { session },
    } = await supabase.auth.getSession()
    const accessToken = session?.access_token

    const referralCode =
      typeof window !== "undefined"
        ? localStorage.getItem("referral_code")
        : null

    const res = await fetch("/api/create-checkout-session", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
      },
      body: JSON.stringify({
        userId,
        referralCode,
      }),
    })

    const data = await res.json()
    console.log("Checkout API response from login:", { status: res.status, data })

    if (!res.ok) {
      throw new Error(data?.error || "Checkout failed")
    }

    if (!data.url) {
      throw new Error("Missing checkout URL")
    }

    window.location.href = data.url
    } finally {
      checkoutInFlightRef.current = false
    }
  }

  useEffect(() => {
    if (typeof window === "undefined") return
    const ref = persistReferralCodeFromUrl()
    if (!ref) return
    if (isBetaReferralRef(ref)) {
      setIsLogin(false)
      setIsBetaSignup(true)
    }
  }, [])

  useEffect(() => {
    if (!shouldStartCheckout()) return

    let cancelled = false
    const run = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user || cancelled) return

      try {
        setLoading(true)
        await startCheckoutAfterAuth(user.id)
      } catch (e) {
        if (!cancelled) {
          console.error("Checkout continuation failed:", e)
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    void run()
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (shouldStartCheckout()) return

    let cancelled = false
    const run = async () => {
      const next = getSafeNextPath()
      if (!next) return

      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user || cancelled) return
      router.replace(next)
    }

    void run()
    return () => {
      cancelled = true
    }
  }, [router])

  async function handleSignUp(e: React.MouseEvent<HTMLButtonElement>) {
    console.log("Signup clicked")
    e.preventDefault()
    if (loading) return

    if (!agreedToTerms) {
      showPopup({
        type: "error",
        message:
          "You must agree to the Terms of Service and Privacy Policy before creating an account.",
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
        if (/already registered/i.test(authError.message || "")) {
          showPopup({ type: "error", message: authError.message })
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
        showPopup({ type: "error", message: authError.message })
        return
      }

      const user = data?.user

      console.log("SIGNUP USER:", user)

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

      console.log("✅ PROFILE ENSURED")

      if (ensureResult.created && isBetaReferralRef(referralCode)) {
        notifyAdminBetaSignup("email")
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

      router.push(getSafeNextPath() ?? "/dashboard")
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
    console.log("Login clicked")
    if (loading) return
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

    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (user) {
      const ensureResult = await ensureProfileForUser(supabase, {
        userId: user.id,
        referredBy: readStoredReferralCode(),
        userMetadata: user.user_metadata,
      })
      if (!ensureResult.ok) {
        console.error("ensureProfileForUser after login:", ensureResult.error)
      }

      if (shouldStartCheckout()) {
        try {
          await startCheckoutAfterAuth(user.id)
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
    }

    router.push(getSafeNextPath() ?? "/dashboard")
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

    setGoogleLoading(true)

    try {
    let redirectPath = "/dashboard"
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
  <div className="relative -mt-16 flex min-h-screen items-center justify-center text-white">

    {/* 🔥 FULL BACKGROUND IMAGE */}
    <img
      src="/tradetrax-bg.png"
      alt="bg"
      className="absolute inset-0 w-full h-full object-cover"
    />

    {/* 🔥 DARK OVERLAY (IMPORTANT FOR READABILITY) */}
    <div className="absolute inset-0 bg-black/70 backdrop-blur-sm"></div>

    <button
      type="button"
      onClick={handleBack}
      className="absolute left-3 top-3 z-20 inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/10 bg-white/10 text-base leading-none text-gray-200 backdrop-blur-md transition hover:bg-white/15 hover:text-white md:left-6 md:top-6 md:h-auto md:min-h-[44px] md:w-auto md:gap-2 md:px-4 md:py-2 md:text-sm md:font-medium"
      aria-label="Go back"
    >
      <span aria-hidden="true">←</span>
      <span className="hidden md:inline">Back</span>
    </button>

    {/* 🔥 CONTENT */}
    <div className="relative z-10 flex w-full max-w-6xl flex-col items-center justify-between px-6 md:flex-row">

      {/* LEFT TEXT */}
      <div
        className={`max-w-lg text-center md:text-left ${
          isBetaSignup ? "mb-4 md:mb-0" : "mb-10 md:mb-0"
        }`}
      >
        {isBetaSignup ? (
          <>
            <h1 className="mb-3 text-2xl font-bold leading-tight bg-gradient-to-r from-amber-300 to-emerald-400 bg-clip-text text-transparent sm:text-4xl md:mb-5 md:text-[2.5rem]">
              🎉 Welcome to the TradeTraxs Beta!
            </h1>

            {/* Desktop — full message (unchanged) */}
            <div className="hidden space-y-3 text-base leading-relaxed text-gray-300 md:block">
              <p>
                First off, thank you so much for being a beta tester for TradeTraxs.
              </p>
              <p>
                The fact that you&apos;re here means a lot to me. I&apos;ve spent hundreds of hours
                building this platform, and now I finally get to put it in the hands of likeminded traders.
              </p>
              <p>
                As you use the app, please don&apos;t be afraid to tell me what you love, what you
                hate, what&apos;s confusing, or what features you wish existed. Honest feedback is
                the most valuable thing you can give me right now.
              </p>
              <p>
                You have a real opportunity to help shape the future of TradeTraxs. Many of the
                features and improvements added during beta will come directly from suggestions made
                by you all.
              </p>
              <p>
                Thank you again for taking the time to test the platform. I&apos;m excited to hear
                your feedback and continue building something awesome together.
              </p>
              <p className="pt-1 font-medium text-amber-100/90"> — Nick</p>
            </div>

            {/* Mobile — teaser + expandable remainder */}
            <div className="md:hidden">
              <p className="text-sm leading-relaxed text-gray-300">
                First off, thank you so much for being a beta tester for TradeTraxs.
              </p>
              <div
                className={`grid transition-[grid-template-rows] duration-300 ease-in-out ${
                  betaWelcomeExpanded ? "grid-rows-[1fr]" : "grid-rows-[0fr]"
                }`}
              >
                <div className="overflow-hidden">
                  <div className="space-y-3 pt-3 text-sm leading-relaxed text-gray-300">
                    <p>
                      The fact that you&apos;re here means a lot to me. I&apos;ve spent hundreds of hours
                      building this platform, and now I finally get to put it in the hands of likeminded traders.
                    </p>
                    <p>
                      As you use the app, please don&apos;t be afraid to tell me what you love, what you
                      hate, what&apos;s confusing, or what features you wish existed. Honest feedback is
                      the most valuable thing you can give me right now.
                    </p>
                    <p>
                      You have a real opportunity to help shape the future of TradeTraxs. Many of the
                      features and improvements added during beta will come directly from suggestions made
                      by you all.
                    </p>
                    <p>
                      Thank you again for taking the time to test the platform. I&apos;m excited to hear
                      your feedback and continue building something awesome together.
                    </p>
                    <p className="font-medium text-amber-100/90"> — Nick</p>
                  </div>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setBetaWelcomeExpanded((open) => !open)}
                aria-expanded={betaWelcomeExpanded}
                className="mt-2 text-sm font-medium text-amber-300/90 underline-offset-2 transition hover:text-amber-200 hover:underline"
              >
                {betaWelcomeExpanded ? "Read Less" : "Read More"}
              </button>
            </div>
          </>
        ) : (
          <>
            <p className="text-sm tracking-widest text-blue-300 mb-4">
              WELCOME TO
            </p>

            <h1 className="text-5xl font-bold mb-4 bg-gradient-to-r from-blue-400 to-teal-300 bg-clip-text text-transparent">
              TradeTraxs
            </h1>

            <p className="text-lg text-gray-300">
              Track. Analyze. Socialize. Dominate your trading.
            </p>
          </>
        )}
      </div>

      {/* RIGHT LOGIN CARD */}
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-white/10 p-8 shadow-2xl backdrop-blur-xl">

        {/* Toggle */}
        <div
          className="flex bg-white/10 rounded-xl p-1 mb-6"
          role="tablist"
          aria-label="Login or sign up"
        >
          <button
            type="button"
            onClick={() => {
              setIsLogin(true)
              setAgreedToTerms(false)
            }}
            className={`flex-1 py-2 rounded-lg font-semibold transition ${
              isLogin ? "bg-white text-black" : "text-white"
            }`}
          >
            Login
          </button>
          <button
            type="button"
            onClick={() => setIsLogin(false)}
            className={`flex-1 py-2 rounded-lg font-semibold transition ${
              !isLogin ? "bg-white text-black" : "text-white"
            }`}
          >
            Sign Up
          </button>
        </div>

        <h2 className="text-xl font-semibold mb-6 text-center">
          {isLogin ? "Sign in to continue" : "Create your account"}
        </h2>

        {!isLogin && (
          <label className="mb-5 flex cursor-pointer items-start gap-3 text-left text-sm leading-snug text-gray-300">
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

        <button
          type="button"
          onClick={handleGoogleLogin}
          disabled={googleLoading || loading || (!isLogin && !agreedToTerms)}
          className="mb-4 w-full rounded-xl bg-white py-3 font-medium text-black transition hover:scale-105 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {googleLoading ? "Redirecting…" : "Continue with Google"}
        </button>

        <div className="text-center text-gray-400 text-sm mb-4">or</div>

        {!isLogin && (
          <input
            type="text"
            placeholder="Full Name"
            className="w-full mb-4 px-4 py-3 rounded-xl bg-white/10 border border-white/10 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        )}

        <form
          onSubmit={(e) => {
            e.preventDefault()
            if (isLogin) handleLogin()
          }}
        >
          <input
            type="email"
            placeholder="Email"
            autoComplete="email"
            className="w-full mb-4 px-4 py-3 rounded-xl bg-white/10 border border-white/10 text-white focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />

          <AuthPasswordInput
            placeholder="Password"
            autoComplete={isLogin ? "current-password" : "new-password"}
            className="w-full mb-6 px-4 py-3 rounded-xl bg-white/10 border border-white/10 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />

          {isLogin && (
            <button
              type="button"
              onClick={() => setShowReset(!showReset)}
              className="text-sm text-blue-400 hover:underline -mt-3 mb-4"
            >
              Forgot password?
            </button>
          )}

          <button
            type={isLogin ? "submit" : "button"}
            disabled={loading || (!isLogin && !agreedToTerms)}
            onClick={isLogin ? undefined : handleSignUp}
            className="w-full bg-gradient-to-r from-blue-500 to-teal-400 py-3 rounded-xl font-semibold hover:scale-105 transition disabled:opacity-60 disabled:hover:scale-100"
          >
            {loading ? "Loading..." : isLogin ? "Login" : "Create Account"}
          </button>
        </form>

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

        <p className="mt-6 text-center text-xs text-gray-500">
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