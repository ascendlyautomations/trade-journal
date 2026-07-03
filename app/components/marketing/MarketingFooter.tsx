import Link from "next/link"
import { LANDING_BRAND_TAGLINE } from "@/lib/landingFlagships"

const FOOTER_LINK_CLASS =
  "text-sm text-gray-400 transition hover:text-gray-300"

function FooterLink({
  href,
  children,
}: {
  href: string
  children: React.ReactNode
}) {
  return (
    <Link href={href} className={FOOTER_LINK_CLASS}>
      {children}
    </Link>
  )
}

function FooterMuted({ children }: { children: React.ReactNode }) {
  return <span className={`${FOOTER_LINK_CLASS} cursor-default`}>{children}</span>
}

export default function MarketingFooter() {
  return (
    <footer className="border-t border-white/10 py-10">
      <div className="mx-auto max-w-5xl px-6">
        <p className="text-center text-sm text-gray-500">{LANDING_BRAND_TAGLINE}</p>
        <div className="mt-8 grid gap-8 sm:grid-cols-2 sm:gap-10">
          <nav aria-label="Company" className="text-center sm:text-left">
            <p className="text-xs font-semibold uppercase tracking-wide text-gray-500">Company</p>
            <ul className="mt-3 space-y-2">
              <li>
                <FooterMuted>About (Coming Soon)</FooterMuted>
              </li>
              <li>
                <FooterLink href="/contact">Contact</FooterLink>
              </li>
              <li>
                <FooterLink href="/affiliate">Affiliate Program</FooterLink>
              </li>
              <li>
                <FooterLink href="/community-guidelines">Community Guidelines</FooterLink>
              </li>
              <li>
                <FooterLink href="/creator-guidelines">Creator Guidelines</FooterLink>
              </li>
              <li>
                <FooterLink href="/legal">Legal</FooterLink>
              </li>
            </ul>
          </nav>
          <nav aria-label="Legal" className="text-center sm:text-left">
            <p className="text-xs font-semibold uppercase tracking-wide text-gray-500">Legal</p>
            <ul className="mt-3 space-y-2">
              <li>
                <FooterLink href="/privacy">Privacy Policy</FooterLink>
              </li>
              <li>
                <FooterLink href="/terms">Terms of Service</FooterLink>
              </li>
            </ul>
          </nav>
        </div>
      </div>
    </footer>
  )
}
