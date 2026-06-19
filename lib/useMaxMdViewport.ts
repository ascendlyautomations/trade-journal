"use client"

import { useEffect, useState } from "react"

/** Matches Tailwind `md` (768px) — same breakpoint as `DetailModalShell` split layout. */
const MAX_MD_QUERY = "(max-width: 767px)"

export function useMaxMdViewport(): boolean {
  const [matches, setMatches] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return

    const mq = window.matchMedia(MAX_MD_QUERY)
    const sync = () => setMatches(mq.matches)
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  }, [])

  return matches
}
