"use client"

import { useEffect, useState, type ReactNode } from "react"
import { NAVBAR_BRAND_LINK_CLASS } from "@/lib/navbarBrand"

export const INSTAGRAM_AD_WIDTH = 1080
export const INSTAGRAM_AD_HEIGHT = 1350

type InstagramAdShellProps = {
  title: string
  subtitle: string
  children: ReactNode
  /** Extra wait (ms) after fonts/charts before marking ready for screenshots. */
  settleMs?: number
}

/**
 * Fixed 1080×1350 Instagram portrait frame — no site chrome.
 * Sets `data-marketing-ready="true"` once fonts and paint have settled.
 */
export default function InstagramAdShell({
  title,
  subtitle,
  children,
  settleMs = 900,
}: InstagramAdShellProps) {
  const [ready, setReady] = useState(false)

  useEffect(() => {
    let cancelled = false
    let timer: ReturnType<typeof setTimeout> | undefined

    async function settle() {
      try {
        if (typeof document !== "undefined" && document.fonts?.ready) {
          await document.fonts.ready
        }
      } catch {
        /* ignore font readiness failures */
      }

      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          timer = setTimeout(() => {
            if (!cancelled) setReady(true)
          }, settleMs)
        })
      })
    }

    void settle()
    return () => {
      cancelled = true
      if (timer) clearTimeout(timer)
    }
  }, [settleMs])

  return (
    <div
      data-marketing-ad
      data-marketing-ready={ready ? "true" : "false"}
      className="relative overflow-hidden text-white"
      style={{
        width: INSTAGRAM_AD_WIDTH,
        height: INSTAGRAM_AD_HEIGHT,
        background:
          "linear-gradient(135deg, #1e3a8a 0%, #1e3a8a 28%, #0f766e 62%, #065f46 100%)",
      }}
    >
      {/* Soft depth — matches product atmosphere without fake UI chrome */}
      <div
        className="pointer-events-none absolute inset-0"
        aria-hidden
        style={{
          background:
            "radial-gradient(ellipse 80% 50% at 50% -10%, rgba(96,165,250,0.18) 0%, transparent 55%), radial-gradient(ellipse 60% 40% at 80% 90%, rgba(52,211,153,0.12) 0%, transparent 50%)",
        }}
      />

      <div className="relative flex h-full flex-col px-14 pb-14 pt-12">
        <header className="shrink-0 text-center">
          <p className={`${NAVBAR_BRAND_LINK_CLASS} text-3xl tracking-tight`}>
            TradeTraxs
          </p>
          <h1 className="mt-5 text-[2.75rem] font-extrabold leading-tight tracking-tight text-white drop-shadow-lg">
            {title}
          </h1>
          <p className="mx-auto mt-3 max-w-[880px] text-xl leading-relaxed text-gray-300">
            {subtitle}
          </p>
        </header>

        <div className="mt-10 flex min-h-0 flex-1 flex-col justify-center">
          <div className="pointer-events-none mx-auto w-full max-w-[960px]">
            {children}
          </div>
        </div>
      </div>
    </div>
  )
}
