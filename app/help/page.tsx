"use client"

import Link from "next/link"
import Navbar from "@/app/components/Navbar"

const HELP_OPTIONS = [
  {
    href: "/support",
    title: "Contact Support",
    description:
      "Account, billing, CSV imports, and other issues. Submit a ticket and track your requests.",
    cta: "Open support",
  },
  {
    href: "/feedback",
    title: "Submit Feedback",
    description: "Product ideas, improvements, and general suggestions for the TradeTrax team.",
    cta: "Send feedback",
  },
] as const

export default function HelpCenterPage() {
  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 py-8 text-white md:px-6">
        <div className="mx-auto w-full max-w-2xl space-y-8">
          <header className="text-center">
            <h1 className="text-2xl font-semibold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent md:text-3xl">
              Help Center
            </h1>
            <p className="mt-2 text-sm text-gray-300">
              Choose how you&apos;d like to reach us. For beta bugs, use Report bug from your account menu.
            </p>
          </header>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            {HELP_OPTIONS.map((option) => (
              <Link
                key={option.href}
                href={option.href}
                className="group rounded-2xl border border-white/10 bg-white/10 p-5 shadow-2xl backdrop-blur-xl transition hover:border-white/20 hover:bg-white/15"
              >
                <h2 className="text-lg font-semibold text-white group-hover:text-blue-200">
                  {option.title}
                </h2>
                <p className="mt-2 text-sm leading-relaxed text-gray-300">{option.description}</p>
                <span className="mt-4 inline-block text-sm font-medium text-emerald-400 group-hover:text-emerald-300">
                  {option.cta} →
                </span>
              </Link>
            ))}
          </div>
        </div>
      </div>
    </>
  )
}
