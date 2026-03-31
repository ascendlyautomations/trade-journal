"use client"

import { useEffect, useState } from "react"
import { supabase } from "../lib/supabaseClient"
import { useRouter } from "next/navigation"
import Navbar from "./components/Navbar"

export default function LandingPage() {
  const router = useRouter()
  const [user, setUser] = useState<any>(null)

  useEffect(() => {
    checkUser()
  }, [])

  async function checkUser() {
    const {
      data: { user }
    } = await supabase.auth.getUser()
    setUser(user)
  }

  return (
    <>
      <Navbar />

      {/* 🔥 NEW BLUE → GREEN THEME */}
      <div className="relative min-h-screen text-gray-100 overflow-hidden">
        {/* 🔥 BACKGROUND IMAGE */}
      <div className="absolute inset-0">
        <img
          src="/hero.png"
          className="w-full h-full object-cover opacity-40"
style={{ objectPosition: "15% center" }}
        />
      </div>
      {/* 🔥 DARK OVERLAY */}
      <div className="absolute inset-0 bg-gradient-to-br from-[#0f172a]/60 via-[#1e293b]/60 to-[#065f46]/60" />

        {/* HERO */}
        <div className="relative z-10 flex flex-col items-center text-center px-6 py-32">

          {/* 🔥 GLOW */}
          <div className="absolute inset-0 bg-gradient-to-r from-blue-500/10 via-emerald-500/10 to-transparent blur-3xl opacity-30" />

          <h1 className="text-6xl font-bold mb-6 leading-tight z-10">
            Trade Smarter.
            <br />
            <span className="bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
              Not Harder.
            </span>
          </h1>

          <p className="text-lg text-gray-400 max-w-xl mb-10 z-10">
            Track your trades, analyze performance, and fix your mistakes faster.
            Built for serious traders.
          </p>

          <div className="flex gap-4 z-10">

            <button
              onClick={() => router.push("/login")}
              className="bg-emerald-500 hover:bg-emerald-600 px-6 py-3 rounded-lg font-semibold transition"
            >
              Click For 7 Days Free!
            </button>

            <button
              onClick={() => router.push("/app")}
              className="border border-white/20 px-6 py-3 rounded-lg hover:bg-white/10 transition"
            >
              Preview Site
            </button>

            {user && (
              <button
                onClick={() => router.push("/app")}
                className="bg-green-400 text-black px-6 py-3 rounded-lg font-semibold"
              >
                Return to Profile
              </button>
            )}

          </div>

        </div>

        {/* FEATURES */}
        <div className="max-w-6xl mx-auto px-6 py-20 grid md:grid-cols-3 gap-8">

          <div className="p-6 bg-white/5 border border-white/10 backdrop-blur-md rounded-xl">
            <h3 className="text-xl font-semibold mb-2 text-emerald-300">📊 Track Everything</h3>
            <p className="text-gray-400 text-sm">
              Log trades, track P&L, and analyze your performance across all accounts.
            </p>
          </div>

          <div className="p-6 bg-white/5 border border-white/10 backdrop-blur-md rounded-xl">
            <h3 className="text-xl font-semibold mb-2 text-emerald-300">📸 Visual Review</h3>
            <p className="text-gray-400 text-sm">
              Upload screenshots and break down exactly what you did right or wrong.
            </p>
          </div>

          <div className="p-6 bg-white/5 border border-white/10 backdrop-blur-md rounded-xl">
            <h3 className="text-xl font-semibold mb-2 text-emerald-300">⚡ Improve Faster</h3>
            <p className="text-gray-400 text-sm">
              Identify patterns and mistakes that are costing you money.
            </p>
          </div>

        </div>

        {/* HOW IT WORKS */}
        <div id="how" className="text-center py-24 px-6">

  {/* 🔥 TITLE */}
  <h2 className="text-4xl font-extrabold mb-14 text-white drop-shadow-lg tracking-tight">
    How It Works
  </h2>

  {/* 🔥 STEPS */}
  <div className="grid md:grid-cols-3 gap-8 max-w-6xl mx-auto">

    {/* STEP 1 */}
    <div className="bg-white/10 backdrop-blur-md p-8 rounded-xl border border-white/20 hover:scale-105 transition">

      <h3 className="text-xl font-semibold mb-3 text-emerald-300">
        1. Log Your Trades
      </h3>

      <p className="text-gray-200 text-sm leading-relaxed">
        Enter your trades in seconds with everything that matters -
        P&L, risk-reward, session, and detailed notes.
      </p>

    </div>

    {/* STEP 2 */}
    <div className="bg-white/10 backdrop-blur-md p-8 rounded-xl border border-white/20 hover:scale-105 transition">

      <h3 className="text-xl font-semibold mb-3 text-emerald-300">
        2. See Exactly What You Saw
      </h3>

      <p className="text-gray-200 text-sm leading-relaxed">
        Upload screenshots and revisit your trades with full context -
        your levels, zones, session sweeps, and confluences exactly how you saw them in the moment.
      </p>

    </div>

    {/* STEP 3 */}
    <div className="bg-white/10 backdrop-blur-md p-8 rounded-xl border border-white/20 hover:scale-105 transition">

      <h3 className="text-xl font-semibold mb-3 text-emerald-300">
        3. Fix Mistakes & Improve Faster
      </h3>

      <p className="text-gray-200 text-sm leading-relaxed">
        Identify patterns like overtrading, poor entries, or bad risk management -
        and correct them with real data and visual feedback.
      </p>

    </div>

  </div>

</div>

        {/* PRICING */}
        <div id="pricing" className="py-20 px-6 text-center">

          <h2 className="text-3xl font-bold mb-10">Pricing</h2>

          <div className="flex justify-center">

            <div className="bg-white/5 border border-white/10 backdrop-blur-md p-8 rounded-xl w-80">

              <h3 className="text-xl font-semibold mb-4">Starter</h3>

              <p className="text-4xl font-bold mb-4">$0</p>

              <p className="text-gray-400 text-sm mb-6">
                Perfect for getting started
              </p>

              <button
                onClick={() => router.push("/login")}
                className="bg-emerald-500 hover:bg-emerald-600 px-6 py-3 rounded-lg w-full"
              >
                Get Started
              </button>

            </div>

          </div>

        </div>

        {/* FOOTER */}
        <div className="text-center text-gray-500 text-sm py-10 border-t border-white/10">
          Built for traders who actually want to improve.
        </div>

      </div>
    </>
  )
}