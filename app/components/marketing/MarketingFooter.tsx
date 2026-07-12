import Link from "next/link"
import { LANDING_BRAND_TAGLINE } from "@/lib/landingFlagships"

const FOOTER_DESCRIPTION =
  "The all-in-one platform to journal, analyze, and socialize your trading."

const TRADETRAXS_INSTAGRAM_URL =
  "https://www.instagram.com/tradetraxs/"

const TRADETRAXS_TIKTOK_URL = "https://www.tiktok.com/@tradetraxs"

const TRADETRAXS_YOUTUBE_URL = "https://www.youtube.com/@TradeTraxs"

const FOOTER_LINK_CLASS =
  "text-[13px] text-gray-400 transition hover:text-gray-300"

const FOOTER_HEADING_CLASS =
  "text-[10px] font-medium uppercase tracking-[0.14em] text-gray-500"

const FOOTER_SOCIAL_ICON_BUTTON =
  "inline-flex h-9 w-9 items-center justify-center rounded-lg border border-white/10 bg-white/[0.03] text-gray-400 transition duration-200 hover:scale-105 hover:border-emerald-400/30 hover:bg-white/[0.06] hover:text-emerald-300 motion-reduce:transition-none motion-reduce:hover:scale-100"

function InstagramIcon({ className = "h-4 w-4" }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" aria-hidden>
      <rect
        x="3"
        y="3"
        width="18"
        height="18"
        rx="5"
        stroke="currentColor"
        strokeWidth="1.75"
      />
      <circle cx="12" cy="12" r="4" stroke="currentColor" strokeWidth="1.75" />
      <circle cx="17.25" cy="6.75" r="1.1" fill="currentColor" />
    </svg>
  )
}

function TikTokIcon({ className = "h-4 w-4" }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M16.6 5.82s.51.5 0 0A4.28 4.28 0 0 1 15.54 3h-3.09v12.4a2.59 2.59 0 0 1-2.59 2.5c-1.42 0-2.6-1.16-2.6-2.6 0-1.72 1.66-3.01 3.37-2.48V9.66c-3.45-.46-6.5 2.05-6.5 5.64 0 3.33 2.76 5.7 5.69 5.7 3.14 0 5.69-2.55 5.69-5.7V9.01a7.35 7.35 0 0 0 4.3 1.38V7.3a4.1 4.1 0 0 1-1-.48z" />
    </svg>
  )
}

function YouTubeIcon({ className = "h-4 w-4" }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M21.6 7.2a2.5 2.5 0 0 0-1.8-1.8C17.9 5 12 5 12 5s-5.9 0-7.8.4A2.5 2.5 0 0 0 2.4 7.2 26 26 0 0 0 2 12a26 26 0 0 0 .4 4.8 2.5 2.5 0 0 0 1.8 1.8C6.1 19 12 19 12 19s5.9 0 7.8-.4a2.5 2.5 0 0 0 1.8-1.8A26 26 0 0 0 22 12a26 26 0 0 0-.4-4.8zM10 15.5v-7l6 3.5-6 3.5z" />
    </svg>
  )
}

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

function FooterNavSection({
  title,
  label,
  children,
}: {
  title: string
  label: string
  children: React.ReactNode
}) {
  return (
    <nav aria-label={label} className="text-left">
      <p className={FOOTER_HEADING_CLASS}>{title}</p>
      <ul className="mt-2.5 space-y-1.5 md:space-y-2">{children}</ul>
    </nav>
  )
}

function FooterSocialLinks({ className = "" }: { className?: string }) {
  return (
    <div className={className}>
      <p className={FOOTER_HEADING_CLASS}>Follow us</p>
      <ul className="mt-2.5 flex items-center gap-2" aria-label="Social media">
        <li>
          <a
            href={TRADETRAXS_INSTAGRAM_URL}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="TradeTraxs on Instagram"
            className={FOOTER_SOCIAL_ICON_BUTTON}
          >
            <InstagramIcon />
          </a>
        </li>
        <li>
          <a
            href={TRADETRAXS_TIKTOK_URL}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="TradeTraxs on TikTok"
            className={FOOTER_SOCIAL_ICON_BUTTON}
          >
            <TikTokIcon />
          </a>
        </li>
        <li>
          <a
            href={TRADETRAXS_YOUTUBE_URL}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="TradeTraxs on YouTube"
            className={FOOTER_SOCIAL_ICON_BUTTON}
          >
            <YouTubeIcon />
          </a>
        </li>
      </ul>
    </div>
  )
}

export default function MarketingFooter() {
  return (
    <footer className="border-t border-white/10 py-6 md:py-8">
      <div className="mx-auto max-w-5xl px-4 md:max-w-6xl md:px-6 lg:max-w-7xl">
        {/* Mobile — unchanged from prior optimization */}
        <div className="md:hidden">
          <div className="text-center">
            <Link
              href="/"
              className="mb-2 inline-block bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-lg font-bold text-transparent"
            >
              TradeTraxs
            </Link>
            <p className="text-center text-xs leading-snug text-gray-500">
              {LANDING_BRAND_TAGLINE}
            </p>
          </div>

          <div className="mt-4 grid grid-cols-2 gap-x-5 gap-y-3">
            <nav aria-label="Product" className="text-left">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                Product
              </p>
              <ul className="mt-2 space-y-1.5">
                <li>
                  <FooterLink href="/pricing">Pricing</FooterLink>
                </li>
                <li>
                  <FooterLink href="/faq">FAQ</FooterLink>
                </li>
                <li>
                  <FooterLink href="/explore">Explore</FooterLink>
                </li>
                <li>
                  <FooterLink href="/leaderboard">Leaderboard</FooterLink>
                </li>
              </ul>
            </nav>
            <nav aria-label="Company" className="text-left">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                Company
              </p>
              <ul className="mt-2 space-y-1.5">
                <li>
                  <FooterLink href="/about">About</FooterLink>
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
              </ul>
            </nav>
            <nav aria-label="Legal" className="text-left">
              <p className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                Legal
              </p>
              <ul className="mt-2 space-y-1.5">
                <li>
                  <FooterLink href="/privacy">Privacy Policy</FooterLink>
                </li>
                <li>
                  <FooterLink href="/terms">Terms of Service</FooterLink>
                </li>
                <li>
                  <FooterLink href="/refund-policy">Refund Policy</FooterLink>
                </li>
                <li>
                  <FooterLink href="/cookie-policy">Cookie Policy</FooterLink>
                </li>
                <li>
                  <FooterLink href="/acceptable-use">Acceptable Use Policy</FooterLink>
                </li>
                <li>
                  <FooterLink href="/copyright">Copyright &amp; DMCA</FooterLink>
                </li>
                <li>
                  <FooterLink href="/legal">Legal</FooterLink>
                </li>
              </ul>
            </nav>
          </div>
        </div>

        {/* Desktop — four-column SaaS layout */}
        <div className="hidden gap-8 md:grid md:grid-cols-2 lg:grid-cols-4 lg:gap-10 xl:gap-12">
          <div className="text-left">
            <Link
              href="/"
              className="inline-block bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-lg font-bold text-transparent"
            >
              TradeTraxs
            </Link>
            <p className="mt-2 max-w-xs text-[13px] leading-relaxed text-gray-500">
              {FOOTER_DESCRIPTION}
            </p>
            <FooterSocialLinks className="mt-4" />
          </div>

          <FooterNavSection title="Product" label="Product">
            <li>
              <FooterLink href="/pricing">Pricing</FooterLink>
            </li>
            <li>
              <FooterLink href="/faq">FAQ</FooterLink>
            </li>
            <li>
              <FooterLink href="/explore">Explore</FooterLink>
            </li>
            <li>
              <FooterLink href="/leaderboard">Leaderboard</FooterLink>
            </li>
            <li>
              <FooterLink href="/affiliate">Affiliate Program</FooterLink>
            </li>
          </FooterNavSection>

          <FooterNavSection title="Company" label="Company">
            <li>
              <FooterLink href="/about">About</FooterLink>
            </li>
            <li>
              <FooterLink href="/contact">Contact</FooterLink>
            </li>
            <li>
              <FooterLink href="/community-guidelines">Community Guidelines</FooterLink>
            </li>
            <li>
              <FooterLink href="/creator-guidelines">Creator Guidelines</FooterLink>
            </li>
          </FooterNavSection>

          <FooterNavSection title="Legal" label="Legal">
            <li>
              <FooterLink href="/privacy">Privacy Policy</FooterLink>
            </li>
            <li>
              <FooterLink href="/terms">Terms of Service</FooterLink>
            </li>
            <li>
              <FooterLink href="/refund-policy">Refund Policy</FooterLink>
            </li>
            <li>
              <FooterLink href="/cookie-policy">Cookie Policy</FooterLink>
            </li>
            <li>
              <FooterLink href="/acceptable-use">Acceptable Use Policy</FooterLink>
            </li>
            <li>
              <FooterLink href="/copyright">Copyright &amp; DMCA</FooterLink>
            </li>
            <li>
              <FooterLink href="/legal">Legal</FooterLink>
            </li>
          </FooterNavSection>
        </div>
      </div>
    </footer>
  )
}
