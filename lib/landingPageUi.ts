"use client"

import { useEffect, useRef, useState } from "react"

/** Shared glass panel (no animation — use on static shells if needed). */
export const LANDING_GLASS_SURFACE =
  "rounded-2xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 backdrop-blur-md"

/**
 * Interactive landing card: glass + hover scale/glow (original TradeTraxs).
 */
export const LANDING_CARD_FULL = `${LANDING_GLASS_SURFACE} transition-[opacity,transform] duration-[400ms] ease-out hover:z-[1] hover:scale-[1.02] hover:border-emerald-400/25 hover:shadow-[0_0_28px_rgba(52,211,153,0.14)] motion-reduce:transition-none`

export const LANDING_CARD_PADDING = "p-6 md:p-7"

export const LANDING_TITLE_GRADIENT =
  "bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent"

export const LANDING_SECTION_SHELL = "mx-auto w-full max-w-6xl px-6"

export const LANDING_SECTION_SPACING = "py-20 md:py-28"

export const LANDING_SECTION_BORDER = "border-t border-white/10"

export const LANDING_EYEBROW =
  "text-xs font-medium uppercase tracking-[0.2em] text-emerald-400/90"

export const LANDING_HEADLINE =
  "text-4xl font-bold tracking-tight text-white md:text-5xl lg:text-6xl"

export const LANDING_HEADLINE_SM =
  "text-3xl font-extrabold tracking-tight text-white drop-shadow-lg md:text-4xl"

export const LANDING_LEAD = "text-lg leading-relaxed text-gray-400 md:text-xl"

export const LANDING_BODY = "text-base leading-relaxed text-gray-400"

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
