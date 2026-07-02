"use client"

import { useEffect, useState, type ReactNode } from "react"
import DemoBanner from "@/app/demo/components/DemoBanner"
import { DemoModeProvider } from "@/lib/demo/DemoModeContext"
import {
  isDemoModeActive,
  subscribeDemoModeChanges,
} from "@/lib/demo/demoMode"

function DemoBannerInset({ children }: { children: ReactNode }) {
  const [active, setActive] = useState(false)

  useEffect(() => {
    const sync = () => setActive(isDemoModeActive())
    sync()
    return subscribeDemoModeChanges(sync)
  }, [])

  return (
    <>
      {active ? <DemoBanner /> : null}
      <div className={active ? "pt-12" : undefined}>{children}</div>
    </>
  )
}

export default function DemoAppShell({ children }: { children: ReactNode }) {
  return (
    <DemoModeProvider>
      <DemoBannerInset>{children}</DemoBannerInset>
    </DemoModeProvider>
  )
}
