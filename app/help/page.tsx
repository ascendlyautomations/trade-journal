"use client"

import Link from "next/link"
import Navbar from "@/app/components/Navbar"
import {
  submissionPageShell,
  submissionSubtitle,
  submissionTitle,
} from "@/lib/submissionFormStyles"

const HELP_CARD_CLASS =
  "group flex h-full flex-col rounded-2xl border border-white/10 bg-white/10 p-5 shadow-2xl backdrop-blur-xl transition-all duration-200 hover:scale-[1.02] hover:border-white/20 hover:bg-white/15 motion-reduce:hover:scale-100 md:p-6"

const HELP_CARD_ICON_WRAPPER =
  "mb-4 flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-white/10 bg-white/10 text-blue-300 transition group-hover:border-blue-400/30 group-hover:bg-blue-500/15 group-hover:text-blue-200"

const HELP_CARD_BUTTON =
  "mt-auto inline-flex w-full items-center justify-center rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-500"

function SupportIcon({ className }: { className?: string }) {
  return (
    <svg className={className} width="24" height="24" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M4 10.5V8a8 8 0 0 1 16 0v2.5M6 10.5h12a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-5.5a2 2 0 0 1 2-2z"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path
        d="M12 14v3"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
      />
    </svg>
  )
}

function FeedbackIcon({ className }: { className?: string }) {
  return (
    <svg className={className} width="24" height="24" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5H6l-4 3v-5.5A8.5 8.5 0 1 1 21 11.5z"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function FeatureRequestIcon({ className }: { className?: string }) {
  return (
    <svg className={className} width="24" height="24" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M9 18h6M10 22h4M12 2a6 6 0 0 0-3 11.3V15h6v-1.7A6 6 0 0 0 12 2z"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

const HELP_OPTIONS = [
  {
    href: "/support",
    title: "Contact Support",
    description:
      "Need help using TradeTraxs or having an issue? Reach out and we'll get back to you as soon as possible.",
    cta: "Contact Support",
    Icon: SupportIcon,
  },
  {
    href: "/feedback",
    title: "Submit Feedback",
    description:
      "Tell us what you love, what could be improved, or how we can make TradeTraxs even better.",
    cta: "Submit Feedback",
    Icon: FeedbackIcon,
  },
  {
    href: "/feature-requests",
    title: "Feature Requests",
    description:
      "Have an idea for a new feature? Share it with us and help shape the future of TradeTraxs.",
    cta: "Submit Feature Request",
    Icon: FeatureRequestIcon,
  },
] as const

function HelpOptionCard({
  href,
  title,
  description,
  cta,
  Icon,
}: (typeof HELP_OPTIONS)[number]) {
  return (
    <Link href={href} className={HELP_CARD_CLASS}>
      <div className={HELP_CARD_ICON_WRAPPER}>
        <Icon className="h-6 w-6" />
      </div>
      <h2 className="text-lg font-semibold text-white group-hover:text-blue-100">{title}</h2>
      <p className="mt-2 mb-5 flex-1 text-sm leading-relaxed text-gray-300">{description}</p>
      <span className={HELP_CARD_BUTTON}>{cta}</span>
    </Link>
  )
}

export default function HelpCenterPage() {
  return (
    <>
      <Navbar />
      <div className={submissionPageShell}>
        <div className="mx-auto w-full max-w-5xl space-y-8">
          <header className="text-center">
            <h1 className={submissionTitle}>Need Help?</h1>
            <p className={submissionSubtitle}>
              Choose how you&apos;d like to reach the TradeTraxs team.
            </p>
          </header>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {HELP_OPTIONS.map((option) => (
              <HelpOptionCard key={option.href} {...option} />
            ))}
          </div>
        </div>
      </div>
    </>
  )
}
