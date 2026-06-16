"use client"

import Link from "next/link"
import { BETA_ROOM_SLUG } from "@/lib/betaHub"

export type BetaWelcomeCardProps = {
  onDismiss: () => void
  onImportCsv: () => void
}

const PRIMARY_BTN =
  "rounded-lg bg-gradient-to-r from-amber-500 to-amber-600 px-4 py-2 text-sm font-semibold text-white shadow-md shadow-amber-900/30 transition hover:from-amber-400 hover:to-amber-500"

const SECONDARY_BTN =
  "rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm font-semibold text-white transition hover:bg-white/15"

const TERTIARY_BTN =
  "rounded-lg border border-amber-400/35 bg-amber-500/10 px-4 py-2 text-sm font-semibold text-amber-100 transition hover:bg-amber-500/20"

export default function BetaWelcomeCard({
  onDismiss,
  onImportCsv,
}: BetaWelcomeCardProps) {
  const betaRoomHref = `/trade-rooms?room=${encodeURIComponent(BETA_ROOM_SLUG)}`

  return (
    <div className="rounded-xl border border-amber-400/35 bg-gradient-to-br from-amber-500/10 via-[#0f172a]/40 to-emerald-950/20 p-6 shadow-[0_8px_32px_rgba(0,0,0,0.2),0_0_32px_rgba(245,158,11,0.08)] backdrop-blur-md md:p-8">
      <h2 className="bg-gradient-to-r from-amber-300 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
        🎉 Welcome to the TradeTraxs Beta!
      </h2>

      <div className="mt-4 max-w-2xl space-y-3 text-sm leading-relaxed text-gray-300 md:text-base">
        <p>Thank you for being an early beta tester.</p>
        <p>
          I&apos;ve spent hundreds of hours building TradeTraxs and I&apos;m excited to finally
          get it into the hands of real traders.
        </p>
        <p>
          As you use the platform, don&apos;t be afraid to tell me what you love, what you hate,
          what&apos;s confusing, and what features you wish existed. Honest feedback is the most
          valuable thing you can give me right now.
        </p>
        <p>
          Many improvements during beta will come directly from suggestions made by traders like
          you.
        </p>
        <p>Thank you for helping shape the future of TradeTraxs.</p>
        <p className="pt-1 font-medium text-amber-100/90">— Nick</p>
      </div>

      <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center">
        <Link href="/app" className={`${PRIMARY_BTN} text-center`}>
          Add First Trade
        </Link>
        <button type="button" onClick={onImportCsv} className={SECONDARY_BTN}>
          Import CSV
        </button>
        <Link href={betaRoomHref} className={`${TERTIARY_BTN} text-center`}>
          Join Beta Discussion
        </Link>
      </div>

      <div className="mt-6 border-t border-amber-400/20 pt-5">
        <button
          type="button"
          onClick={onDismiss}
          className="text-sm font-semibold text-amber-200/90 underline-offset-2 transition hover:text-amber-100 hover:underline"
        >
          Let&apos;s Get Started
        </button>
      </div>
    </div>
  )
}
