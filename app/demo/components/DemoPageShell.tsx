import type { ReactNode } from "react"
import { PAGE_HEADING_COLOR_CLASS } from "@/lib/pageHeadingStyles"

type DemoPageShellProps = {
  title: string
  subtitle?: string
  children: ReactNode
}

export default function DemoPageShell({ title, subtitle, children }: DemoPageShellProps) {
  return (
    <div className="mx-auto max-w-6xl px-4 py-8 md:px-6 md:py-10">
      <header className="mb-8">
        <p className="text-xs font-semibold uppercase tracking-wide text-blue-300">Demo</p>
        <h1 className={`mt-1 text-2xl font-semibold md:text-3xl ${PAGE_HEADING_COLOR_CLASS}`}>
          {title}
        </h1>
        {subtitle ? (
          <p className="mt-2 max-w-2xl text-sm text-gray-400 md:text-base">{subtitle}</p>
        ) : null}
      </header>
      {children}
    </div>
  )
}
