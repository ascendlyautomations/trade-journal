"use client"

import Link from "next/link"
import PsychologyCoachChat from "@/app/components/psychology/PsychologyCoachChat"
import PsychologyProGate from "@/app/components/psychology/PsychologyProGate"
import { usePsychologySessionHydration } from "@/lib/psychology/usePsychologySessionHydration"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"

function PsychologyCoachPageContent() {
  useScrollPageTopOnMount()
  const { ready, loadError, facts } = usePsychologySessionHydration()

  if (!ready) {
    return <p className="text-sm text-gray-400">Loading psychology coach…</p>
  }

  if (loadError) {
    return (
      <p className="text-sm text-red-400">
        {loadError}{" "}
        <Link href="/psychology/analytics" className="underline">
          Back to Analytics
        </Link>
      </p>
    )
  }

  if (!facts) {
    return (
      <div className="rounded-xl border border-white/10 bg-white/5 p-8 text-center">
        <p className="font-medium text-white">Coach unavailable</p>
        <p className="mt-2 text-sm text-gray-500">
          Log trades and daily check-ins to unlock coaching from your journal data.
        </p>
        <Link
          href="/psychology/analytics"
          className="mt-4 inline-block text-sm font-medium text-blue-400"
        >
          Psychology Analytics
        </Link>
      </div>
    )
  }

  return <PsychologyCoachChat facts={facts} />
}

export default function PsychologyCoachPage() {
  return (
    <main className="tt-psych-experience mx-auto max-w-2xl px-4 py-8 md:py-10">
      <div className="mb-6">
        <Link
          href="/psychology/analytics"
          className="text-sm text-blue-400 hover:text-blue-300"
        >
          ← Psychology Analytics
        </Link>
      </div>
      <h1 className="mb-6 text-2xl font-semibold text-blue-200">Psychology Coach</h1>
      <PsychologyProGate>
        <PsychologyCoachPageContent />
      </PsychologyProGate>
    </main>
  )
}
