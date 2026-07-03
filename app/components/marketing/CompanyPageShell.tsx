import type { ReactNode } from "react"
import Link from "next/link"

type CompanyPageShellProps = {
  title: string
  subtitle: string
  children: ReactNode
  backHref?: string
  backLabel?: string
  maxWidthClass?: string
}

export function CompanySectionCard({
  title,
  children,
  id,
}: {
  title: string
  children: ReactNode
  id?: string
}) {
  return (
    <section
      id={id}
      className="scroll-mt-28 rounded-xl border border-white/10 bg-[#1e293b]/60 p-6 shadow-lg shadow-black/10 md:p-8"
    >
      <h2 className="text-xl font-semibold text-white">{title}</h2>
      <div className="mt-4 space-y-3 text-sm leading-relaxed text-gray-300 md:text-[15px]">
        {children}
      </div>
    </section>
  )
}

export function CompanyDocumentCard({
  title,
  description,
  href,
  comingSoon = false,
}: {
  title: string
  description: string
  href?: string
  comingSoon?: boolean
}) {
  const className =
    "group flex h-full flex-col rounded-xl border border-white/10 bg-white/[0.06] p-6 shadow-lg shadow-black/20 transition-all duration-200 hover:border-white/20 hover:bg-white/[0.10] motion-reduce:transition-none"

  const inner = (
    <>
      <div className="flex items-start justify-between gap-3">
        <h2 className="text-lg font-semibold text-white group-hover:text-blue-100">{title}</h2>
        {comingSoon ? (
          <span className="shrink-0 rounded-full border border-white/15 bg-white/10 px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-gray-400">
            Coming Soon
          </span>
        ) : null}
      </div>
      <p className="mt-3 flex-1 text-sm leading-relaxed text-gray-400">{description}</p>
      {!comingSoon && href ? (
        <span className="mt-5 inline-flex items-center gap-1 text-sm font-medium text-blue-300 transition group-hover:text-blue-200">
          View Document
          <span aria-hidden>→</span>
        </span>
      ) : null}
    </>
  )

  if (comingSoon || !href) {
    return <div className={`${className} opacity-90`}>{inner}</div>
  }

  return (
    <Link href={href} className={className}>
      {inner}
    </Link>
  )
}

export default function CompanyPageShell({
  title,
  subtitle,
  children,
  backHref = "/",
  backLabel = "← Back to home",
  maxWidthClass = "max-w-3xl",
}: CompanyPageShellProps) {
  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 pb-12 pt-28 text-white sm:px-6 sm:pb-16 sm:pt-32">
      <div className={`mx-auto w-full ${maxWidthClass}`}>
        <p className="mb-8 text-center">
          <Link href={backHref} className="text-sm text-gray-400 transition hover:text-gray-200">
            {backLabel}
          </Link>
        </p>
        <header className="mb-10 text-center md:mb-12">
          <h1 className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent md:text-4xl">
            {title}
          </h1>
          <p className="mx-auto mt-4 max-w-2xl text-sm leading-relaxed text-gray-400 sm:text-base">
            {subtitle}
          </p>
        </header>
        {children}
      </div>
    </div>
  )
}
