import type { ReactNode } from "react"

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
        <h1 className="mt-1 bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-2xl font-semibold text-transparent md:text-3xl">
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
