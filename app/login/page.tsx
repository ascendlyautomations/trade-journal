"use client"

import { useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { useRouter } from "next/navigation"

export default function LoginPage() {
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [name, setName] = useState("")
  const [username, setUsername] = useState("")
  const [isSignup, setIsSignup] = useState(false)
  const [loading, setLoading] = useState(false)

  const router = useRouter()

  async function handleSignUp(e: React.MouseEvent<HTMLButtonElement>) {
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

    router.push("/trades")
    setLoading(false)
  }

  const handleGoogleLogin = async () => {
    await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${location.origin}/trades`,
      },
    })
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-[#020617] text-white px-4">

      <div className="w-full max-w-md bg-[#0f172a]/80 backdrop-blur border border-white/10 rounded-2xl shadow-2xl p-8">

        {/* TITLE */}
        <h1 className="text-2xl font-bold mb-6 text-center bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
          {isSignup ? "Create Account" : "Welcome Back"}
        </h1>

        {/* GOOGLE BUTTON */}
        <button
          onClick={handleGoogleLogin}
          className="w-full mb-4 bg-white text-black font-medium py-2 rounded-lg hover:bg-gray-200 transition"
        >
          Continue with Google
        </button>

        <div className="text-center text-sm text-gray-400 mb-4">or</div>

        {/* SIGNUP ONLY */}
        {isSignup && (
          <>
            <input
              className="w-full mb-3 p-3 rounded-lg bg-[#020617] border border-white/10 focus:outline-none focus:border-blue-500"
              placeholder="Full Name"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />

            <input
              className="w-full mb-3 p-3 rounded-lg bg-[#020617] border border-white/10 focus:outline-none focus:border-blue-500"
              placeholder="Username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
            />
          </>
        )}

        {/* EMAIL */}
        <input
          className="w-full mb-3 p-3 rounded-lg bg-[#020617] border border-white/10 focus:outline-none focus:border-blue-500"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />

        {/* PASSWORD */}
        <input
          type="password"
          className="w-full mb-5 p-3 rounded-lg bg-[#020617] border border-white/10 focus:outline-none focus:border-blue-500"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />

        {/* MAIN BUTTON */}
        <button
          onClick={isSignup ? handleSignUp : handleLogin}
          disabled={loading}
          className="w-full bg-gradient-to-r from-blue-500 to-emerald-500 py-3 rounded-lg font-semibold hover:opacity-90 transition"
        >
          {loading
            ? "Loading..."
            : isSignup
            ? "Create Account"
            : "Login"}
        </button>

        {/* TOGGLE */}
        <div className="text-center mt-5 text-sm text-gray-400">
          {isSignup ? "Already have an account?" : "Don’t have an account?"}
          <button
            onClick={() => setIsSignup(!isSignup)}
            className="ml-2 text-blue-400 hover:underline"
          >
            {isSignup ? "Login" : "Sign up"}
          </button>
        </div>

      </div>
    </div>
  )
}