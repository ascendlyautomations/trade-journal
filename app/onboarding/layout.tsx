import type { Metadata } from "next"
import type { ReactNode } from "react"

export const metadata: Metadata = {
  title: "Set up your account",
}

/**
 * Full-screen onboarding — no Navbar, no app shell.
 * Root layout `pt-16` is cancelled so the form fills the viewport.
 */
export default function OnboardingLayout({ children }: { children: ReactNode }) {
  return (
    <div className="-mt-16 min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46]">
      {children}
    </div>
  )
}
