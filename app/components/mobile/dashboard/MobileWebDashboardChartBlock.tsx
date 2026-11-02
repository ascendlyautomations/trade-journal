"use client"

import type { ReactNode } from "react"

type MobileWebDashboardChartBlockProps = {
  title: string
  subtitle?: string
  children: ReactNode
}

export default function MobileWebDashboardChartBlock({
  title,
  subtitle,
  children,
}: MobileWebDashboardChartBlockProps) {
  return (
    <section className="flex flex-col gap-1.5">
      <div>
        <h3 className="text-[13px] font-medium leading-tight text-[color:var(--tt-text-muted,#c0cad6)]">
          {title}
        </h3>
        {subtitle ? (
          <p className="mt-0.5 text-[11px] leading-snug text-[color:var(--tt-text-tertiary,#a8b3c2)]">
            {subtitle}
          </p>
        ) : null}
      </div>
      <div className="rounded-[10px] bg-[color:var(--tt-surface-nested,#1a222c)] p-3.5">
        {children}
      </div>
    </section>
  )
}

export function MobileWebDashboardSectionHeader({
  title,
  subtitle,
}: {
  title: string
  subtitle?: string
}) {
  return (
    <div className="px-0.5">
      <h2 className="text-[17px] font-semibold tracking-tight text-[color:var(--tt-text,#f0f3f6)]">
        {title}
      </h2>
      {subtitle ? (
        <p className="mt-0.5 text-[13px] text-[color:var(--tt-text-tertiary,#a8b3c2)]">
          {subtitle}
        </p>
      ) : null}
    </div>
  )
}
