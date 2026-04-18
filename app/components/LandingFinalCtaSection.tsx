"use client"

type Props = {
  checkoutLoading: boolean
  onStartTrial: () => void
  onPreview: () => void
}

export default function LandingFinalCtaSection({ checkoutLoading, onStartTrial, onPreview }: Props) {
  return (
    <section
      className="relative z-10 max-w-4xl mx-auto px-6 py-24 text-center border-t border-white/10"
      aria-labelledby="final-cta-heading"
    >
      <div className="rounded-2xl border border-white/10 bg-gradient-to-br from-white/[0.07] via-white/[0.04] to-emerald-500/[0.06] backdrop-blur-md px-6 py-12 md:px-10 md:py-14 shadow-lg shadow-black/25">
        <h2 id="final-cta-heading" className="text-3xl md:text-4xl font-extrabold text-white tracking-tight mb-4">
          Ready to Trade Smarter?
        </h2>
        <p className="text-gray-400 text-base md:text-lg mb-10 max-w-lg mx-auto leading-relaxed">
          Trades, analytics, community—finally in one stack.
        </p>
        <div className="flex flex-wrap justify-center gap-4">
          <button
            type="button"
            disabled={checkoutLoading}
            onClick={onStartTrial}
            className="bg-emerald-500 hover:bg-emerald-600 disabled:opacity-60 disabled:cursor-not-allowed px-8 py-3.5 rounded-xl font-semibold text-white text-base min-w-[200px]"
          >
            {checkoutLoading ? "Starting trial..." : "Start 14-Day Free Trial"}
          </button>
          <button
            type="button"
            onClick={onPreview}
            className="border border-white/20 px-8 py-3.5 rounded-xl font-semibold hover:bg-white/10 transition text-base min-w-[160px]"
          >
            Preview Site
          </button>
        </div>
      </div>
    </section>
  )
}
