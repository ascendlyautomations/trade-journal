"use client"

import { useEffect, useRef, useState } from "react"

/** Shared glass panel (no animation — use on static shells if needed). */
export const LANDING_GLASS_SURFACE =
  "rounded-2xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 backdrop-blur-md"

/**
 * Interactive landing card: glass + hover scale/glow (original TradeTraxs).
 */
export const LANDING_CARD_FULL = `${LANDING_GLASS_SURFACE} transition-[opacity,transform] duration-[400ms] ease-out hover:z-[1] hover:scale-[1.02] hover:border-emerald-400/25 hover:shadow-[0_0_28px_rgba(52,211,153,0.14)] motion-reduce:transition-none`

/**
 * Shared media frame for Best Trade / Highest RR homepage cards.
 * Re-exports the upload cropper frame (`TRADE_IMAGE_ASPECT` = 4/3).
 */
export {
  TRADE_IMAGE_MEDIA_FRAME_CLASS as LANDING_FEATURED_TRADE_MEDIA_FRAME_CLASS,
  TRADE_IMAGE_MEDIA_FRAME_IMG_CLASS as LANDING_FEATURED_TRADE_MEDIA_IMAGE_CLASS,
} from "@/lib/tradeImageAspect"

export const LANDING_CARD_PADDING = "p-4 md:p-7"

export const LANDING_TITLE_GRADIENT =
  "bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent"

export const LANDING_SECTION_SHELL = "mx-auto w-full max-w-6xl px-4 md:px-6"

export const LANDING_SECTION_SPACING = "py-12 md:py-28"

export const LANDING_SECTION_BORDER = "border-t border-white/10"

/** Gap between section title block and main content. */
export const LANDING_SECTION_CONTENT_GAP = "mt-8 md:mt-14"

/** Gap below section headings before lead copy. */
export const LANDING_LEAD_GAP = "mt-3 md:mt-5"

export const LANDING_EYEBROW =
  "text-xs font-medium uppercase tracking-[0.2em] text-emerald-400/90"

export const LANDING_HEADLINE =
  "text-3xl font-bold tracking-tight text-white md:text-5xl lg:text-6xl"

export const LANDING_HEADLINE_SM =
  "text-2xl font-extrabold tracking-tight text-white drop-shadow-lg md:text-4xl"

/** Feature / analytics section titles (between hero and flagship scale). */
export const LANDING_HEADLINE_SECTION =
  "text-2xl font-extrabold tracking-tight text-white drop-shadow-lg md:text-4xl lg:text-5xl"

export const LANDING_LEAD = "text-base leading-relaxed text-gray-400 md:text-xl"

export const LANDING_BODY = "text-sm leading-relaxed text-gray-400 md:text-base"

/** Primary marketing CTA — compact on mobile, unchanged from md up. */
export const LANDING_CTA_BUTTON =
  "rounded-xl bg-blue-500 px-6 py-3 font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500 md:px-8 md:py-3.5"

export const LANDING_CTA_BUTTON_SECONDARY =
  "rounded-lg border border-white/20 px-6 py-3 font-semibold transition hover:bg-white/10 md:px-8 md:py-3.5"

/** @deprecated Use LANDING_CTA_BUTTON */
export const LANDING_PRIMARY_BUTTON = LANDING_CTA_BUTTON

/** @deprecated Use LANDING_CTA_BUTTON_SECONDARY */
export const LANDING_SECONDARY_BUTTON = LANDING_CTA_BUTTON_SECONDARY

export const LANDING_REVEAL_FROM = "opacity-0 translate-y-5"
export const LANDING_REVEAL_TO = "opacity-100 translate-y-0"

export const LANDING_REVEAL_TRANSITION =
  "motion-reduce:!translate-y-0 motion-reduce:!opacity-100 motion-reduce:transition-none"

export function useLandingReveal() {
  const ref = useRef<HTMLElement | null>(null)
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setVisible(true)
      return
    }
    const el = ref.current
    if (!el) return
    const io = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) {
          setVisible(true)
          io.unobserve(el)
        }
      },
      { threshold: 0.06, rootMargin: "0px 0px -8% 0px" }
    )
    io.observe(el)
    return () => io.disconnect()
  }, [])

  return { ref, visible }
}
