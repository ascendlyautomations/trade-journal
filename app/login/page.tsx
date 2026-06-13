'use client'

import { useState, useEffect } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  isProfilesUsernameConflict,
  normalizeProfileUsername,
  sanitizeUsernameInputForTyping,
  USERNAME_FORMAT_HINT,
} from "@/lib/profileUsername"
import { useRouter } from "next/navigation"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"

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
  const [username, setUsername] = useState("")
  const [isLogin, setIsLogin] = useState(true)
  const [loading, setLoading] = useState(false)
  const [showReset, setShowReset] = useState(false)
  const [resetEmail, setResetEmail] = useState("")
  const [resetMessage, setResetMessage] = useState("")
  const [loadingReset, setLoadingReset] = useState(false)
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
  }

  useEffect(() => {
    if (typeof window === "undefined") return
    const ref = new URLSearchParams(window.location.search).get("ref")
    if (!ref) return
    try {
      localStorage.setItem("referral_code", ref.trim())
    } catch {
      /* ignore */
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
    setLoading(true)

    try {
      const referralCode =
        typeof window !== "undefined"
          ? localStorage.getItem("referral_code")
          : null

      const cleanUsername = normalizeProfileUsername(username ?? "")
      if (!cleanUsername.length) {
        showPopup({ type: "error", message: "Please enter a username" })
        return
      }

      const { data: existingUser, error: usernameLookupErr } = await supabase
        .from("profiles")
        .select("id")
        .eq("username", cleanUsername)
        .maybeSingle()

      if (usernameLookupErr) {
        console.error("Username lookup:", usernameLookupErr)
        showPopup({ type: "error", message: "Could not validate username. Try again." })
        return
      }

      if (existingUser) {
        showPopup({ type: "error", message: "Username already in use" })
        return
      }

      const { data, error: authError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            username: cleanUsername,
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

      const profileRow = {
        id: user.id,
        username: cleanUsername,
        name: (name ?? "").trim(),
        is_pro: false,
        subscription_status: "inactive",
        created_at: new Date().toISOString(),
        referred_by: referralCode || null,
      }

      let profileError = (
        await supabase.from("profiles").insert(profileRow)
      ).error

      if (profileError?.code === "23505" && !isProfilesUsernameConflict(profileError)) {
        profileError = (
          await supabase.from("profiles").upsert(profileRow, {
            onConflict: "id",
          })
        ).error
      }

      if (profileError) {
        if (profileError.code === "23505" && isProfilesUsernameConflict(profileError)) {
          showPopup({ type: "error", message: "Username already in use" })
          return
        }
        console.error("PROFILE INSERT ERROR:", profileError)
        showPopup({ type: "error", message: "Error creating profile" })
        return
      }

      console.log("✅ PROFILE CREATED")

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
  }

  const handleReset = async () => {
    if (!resetEmail) return

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
      className="absolute left-4 top-4 z-20 inline-flex min-h-[44px] items-center gap-2 rounded-lg border border-white/10 bg-white/10 px-3 py-2 text-sm font-medium text-gray-200 backdrop-blur-md transition hover:bg-white/15 hover:text-white md:left-6 md:top-6 md:px-4"
      aria-label="Go back"
    >
      <span aria-hidden="true">←</span>
      Back
    </button>

    {/* 🔥 CONTENT */}
    <div className="relative z-10 w-full max-w-6xl flex flex-col md:flex-row items-center justify-between px-6">

      {/* LEFT TEXT */}
      <div className="mb-10 md:mb-0 max-w-lg text-center md:text-left">
        <p className="text-sm tracking-widest text-blue-300 mb-4">
          WELCOME TO
        </p>

        <h1 className="text-5xl font-bold mb-4 bg-gradient-to-r from-blue-400 to-teal-300 bg-clip-text text-transparent">
          TradeTrax
        </h1>

        <p className="text-lg text-gray-300">
          Track. Analyze. Socialize. Dominate your trading.
        </p>
      </div>

      {/* RIGHT LOGIN CARD */}
      <div className="w-full max-w-md bg-white/10 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl p-8">

        {/* Toggle */}
        <div
          className="flex bg-white/10 rounded-xl p-1 mb-6"
          role="tablist"
          aria-label="Login or sign up"
        >
          <button
            type="button"
            onClick={() => setIsLogin(true)}
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

        <button
          type="button"
          onClick={handleGoogleLogin}
          className="w-full bg-white text-black py-3 rounded-xl mb-4 font-medium hover:scale-105 transition"
        >
          Continue with Google
        </button>

        <div className="text-center text-gray-400 text-sm mb-4">or</div>

        {!isLogin && (
          <>
            <input
              type="text"
              placeholder="Full Name"
              className="w-full mb-4 px-4 py-3 rounded-xl bg-white/10 border border-white/10 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />

            <div className="mb-4">
              <input
                type="text"
                placeholder="username (lowercase only)"
                autoComplete="username"
                className="w-full px-4 py-3 rounded-xl bg-white/10 border border-white/10 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"
                value={username}
                onChange={(e) => {
                  setUsername(sanitizeUsernameInputForTyping(e.target.value))
                }}
              />
              <p className="text-xs text-white/50 mt-1">{USERNAME_FORMAT_HINT}</p>
            </div>
          </>
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
            className="w-full mb-4 px-4 py-3 rounded-xl bg-white/10 border border-white/10 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />

          <input
            type="password"
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
            disabled={loading}
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
      </div>
    </div>
    <FeedbackModal {...feedbackModalProps} />
  </div>
)
}