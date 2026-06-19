import Link from "next/link"
import type { ReactNode } from "react"
import LegalPageBackButton from "./LegalPageBackButton"
import PublicNavbar from "./PublicNavbar"
import { LEGAL_LAST_UPDATED } from "@/lib/legal/contact"

export type LegalSection = {
  id: string
  title: string
  content: ReactNode
}

type LegalDocumentLayoutProps = {
  title: string
  subtitle: string
  sections: LegalSection[]
  relatedHref: { href: string; label: string }
}

export default function LegalDocumentLayout({
  title,
  subtitle,
  sections,
  relatedHref,
}: LegalDocumentLayoutProps) {
  return (
    <>
      <PublicNavbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 pb-16 pt-12 text-gray-100 md:px-6 md:pt-24">
        <article className="mx-auto max-w-3xl">
          <LegalPageBackButton />
          <header className="mb-10 text-center">
            <h1 className="text-3xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent md:text-4xl">
              {title}
            </h1>
            <p className="mt-3 text-sm text-gray-300">{subtitle}</p>
            <p className="mt-2 text-xs text-gray-500">Last updated: {LEGAL_LAST_UPDATED}</p>
          </header>

          <nav
            aria-label="Table of contents"
            className="mb-10 rounded-xl border border-white/10 bg-white/5 p-5 backdrop-blur-sm"
          >
            <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
              On this page
            </h2>
            <ol className="mt-3 space-y-2 text-sm">
              {sections.map((section, index) => (
                <li key={section.id}>
                  <a
                    href={`#${section.id}`}
                    className="text-blue-300 transition hover:text-blue-200"
                  >
                    {index + 1}. {section.title}
                  </a>
                </li>
              ))}
            </ol>
          </nav>

          <div className="space-y-10">
            {sections.map((section) => (
              <section
                key={section.id}
                id={section.id}
                className="scroll-mt-28 rounded-xl border border-white/10 bg-[#1e293b]/60 p-6 shadow-lg shadow-black/10 md:p-8"
              >
                <h2 className="text-xl font-semibold text-white">{section.title}</h2>
                <div className="prose-legal mt-4 space-y-4 text-sm leading-relaxed text-gray-300 [&_a]:text-blue-300 [&_a]:underline [&_a]:underline-offset-2 [&_a:hover]:text-blue-200 [&_li]:ml-4 [&_li]:list-disc [&_strong]:font-semibold [&_strong]:text-gray-200 [&_ul]:space-y-2">
                  {section.content}
                </div>
              </section>
            ))}
          </div>

          <footer className="mt-12 rounded-xl border border-white/10 bg-white/5 p-6 text-center text-sm text-gray-400">
            <p>
              See also:{" "}
              <Link href={relatedHref.href} className="text-blue-300 hover:text-blue-200">
                {relatedHref.label}
              </Link>
            </p>
            <p className="mt-4 text-xs leading-relaxed text-gray-500">
              This document is provided for informational purposes during the TradeTraxs beta.
              It is not legal advice. Have qualified counsel review before relying on it for
              compliance.
            </p>
          </footer>
        </article>
      </div>
    </>
  )
}
