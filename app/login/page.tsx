'use client'

import { useState, useEffect } from "react"
import { supabase } from "@/lib/supabaseClient"
import { useRouter } from "next/navigation"
import { ONBOARDING_FLAG } from "../components/ProfileOnboarding"

export default function LoginPage() {
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [name, setName] = useState("")
  const [username, setUsername] = useState("")
  const [isLogin, setIsLogin] = useState(true)
  const [loading, setLoading] = useState(false)

  const router = useRouter()

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

  async function handleSignUp(e: React.MouseEvent<HTMLButtonElement>) {
    console.log("Signup clicked")
    e.preventDefault()
    setLoading(true)

    try {
      const referralCode =
        typeof window !== "undefined"
          ? localStorage.getItem("referral_code")
          : null

      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            username: username?.trim() || null,
            name: name?.trim() || null,
            referral_code: referralCode || null,
          },
        },
      })

      if (error) {
        if (/already registered/i.test(error.message || "")) {
          alert(error.message)
          return
        }
        console.error(
          "ERROR:",
          JSON.stringify(
            {
              message: error.message,
              name: error.name,
              status: (error as { status?: number }).status,
            },
            null,
            2
          )
        )
        alert(error.message)
        return
      }

      const user = data?.user

      console.log("SIGNUP USER:", user)

      if (!user) {
        alert("Check your email to confirm your account before continuing.")
        return
      }

      const { error: profileError } = await supabase.from("profiles").upsert(
        {
          id: user.id,
          username: username || user.email || `user_${user.id.slice(0, 6)}`,
          name: name || "",
          is_pro: false,
          subscription_status: "inactive",
          created_at: new Date().toISOString(),
        },
        { onConflict: "id" }
      )

      if (profileError) {
        console.error(
          "ERROR:",
          JSON.stringify(profileError, null, 2)
        )
        alert("Profile creation failed")
        return
      }

      console.log("✅ PROFILE CREATED")

      try {
        sessionStorage.setItem(ONBOARDING_FLAG, "1")
      } catch {
        /* ignore private mode */
      }

      if (shouldStartCheckout()) {
        try {
          await startCheckoutAfterAuth(user.id)
          return
        } catch (e) {
          console.error("Checkout after signup failed:", e)
          alert("Signed up, but checkout failed. Please try again from Pricing.")
        }
      }

      router.push("/dashboard")
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
      alert("Something went wrong during signup")
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
      alert(error.message)
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
          alert("Logged in, but checkout failed. Please try again from Pricing.")
          setLoading(false)
          return
        }
      }

      const { data: prof } = await supabase
        .from("profiles")
        .select("username")
        .eq("id", user.id)
        .maybeSingle()

      const missingUsername =
        !prof?.username || String(prof.username).trim() === ""

      if (missingUsername) {
        try {
          sessionStorage.setItem(ONBOARDING_FLAG, "1")
        } catch {
          /* ignore */
        }
        router.push("/dashboard")
        setLoading(false)
        return
      }
    }

    router.push("/trades")
    setLoading(false)
  }

  const handleGoogleLogin = async () => {
    const redirectPath = shouldStartCheckout() ? "/login?next=checkout" : "/trades"
    await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${location.origin}${redirectPath}`,
      },
    })
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

            <input
              type="text"
              placeholder="Username"
              className="w-full mb-4 px-4 py-3 rounded-xl bg-white/10 border border-white/10 focus:outline-none focus:ring-2 focus:ring-blue-400 placeholder-gray-400"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
            />
          </>
        )}

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

        <button
          type="button"
          disabled={loading}
          onClick={isLogin ? handleLogin : handleSignUp}
          className="w-full bg-gradient-to-r from-blue-500 to-teal-400 py-3 rounded-xl font-semibold hover:scale-105 transition disabled:opacity-60 disabled:hover:scale-100"
        >
          {loading ? "Loading..." : isLogin ? "Login" : "Create Account"}
        </button>
      </div>
    </div>
  </div>
)
}