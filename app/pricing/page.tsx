"use client"

import Link from "next/link"
import { useRouter } from "next/navigation"
import PublicNavbar from "../components/PublicNavbar"

export default function PricingPage() {
  const router = useRouter()

  return (
    <>
      <PublicNavbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-6 py-16 text-white">
        <div className="mx-auto max-w-lg text-center">
          <h1 className="mb-4 text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Pricing
          </h1>
          <p className="mb-12 text-sm text-gray-400">
            Simple plans to get you journaling and improving.
          </p>

          <div className="rounded-xl border border-white/10 bg-white/5 p-8 backdrop-blur-md">
            <h2 className="mb-2 text-xl font-semibold">Starter</h2>
            <p className="mb-4 text-4xl font-bold">$0</p>
            <p className="mb-6 text-sm text-gray-400">
              Perfect for getting started
            </p>
            <button
              type="button"
              onClick={() => router.push("/login")}
              className="w-full rounded-lg bg-emerald-500 px-6 py-3 font-semibold text-white hover:bg-emerald-600 transition"
            >
              Get Started
            </button>
          </div>

          <p className="mt-10 text-sm text-gray-500">
            <Link href="/" className="text-blue-400 hover:underline">
              ← Back to home
            </Link>
          </p>
        </div>
      </div>
    </>
  )
}
