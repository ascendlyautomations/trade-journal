import Link from "next/link"
import type { LegalSection } from "@/app/components/LegalDocumentLayout"
import { COMMISSION_RATE } from "@/lib/affiliateEarnings"
import { AFFILIATE_DISCOUNT_PERCENT_OFF } from "@/lib/affiliateStripeDiscount"
import { SUPPORT_EMAIL } from "@/lib/contactEmails"
import { LEGAL_ENTITY_NAME } from "@/lib/legal/contact"
import { SITE_URL } from "@/lib/site"

const COMMISSION_PERCENT = Math.round(COMMISSION_RATE * 100)
/** Matches `affiliate_payout_balance` minimum gate in production database logic. */
const MINIMUM_PAYOUT_USD = 100

export const AFFILIATE_TERMS_SECTIONS: LegalSection[] = [
  {
    id: "overview",
    title: "Overview",
    content: (
      <>
        <p>
          These Affiliate Terms (&quot;Affiliate Terms&quot;) govern participation in the TradeTraxs
          Affiliate Program operated by {LEGAL_ENTITY_NAME} (&quot;TradeTraxs,&quot; &quot;we,&quot;
          &quot;us,&quot; or &quot;our&quot;) at <a href={SITE_URL}>{SITE_URL}</a>. They supplement
          our <Link href="/terms">Terms of Service</Link> and{" "}
          <Link href="/privacy">Privacy Policy</Link>.
        </p>
        <p>
          By applying to or participating in the program, you agree to these Affiliate Terms. If
          you do not agree, do not participate.
        </p>
      </>
    ),
  },
  {
    id: "eligibility",
    title: "Eligibility and Approval",
    content: (
      <>
        <p>
          The program is intended for creators, educators, and community leaders who can promote
          TradeTraxs honestly to an audience of traders. You must have a TradeTraxs account, submit
          an application through the Service, and receive approval before you receive an affiliate
          referral code and dashboard access.
        </p>
        <p>
          We may approve, deny, suspend, or remove affiliates at our discretion. Participation is
          not guaranteed. You must be able to enter a binding agreement and comply with applicable
          laws, including advertising disclosure rules.
        </p>
      </>
    ),
  },
  {
    id: "qualifying-referrals",
    title: "Qualifying Referrals and Attribution",
    content: (
      <>
        <p>
          A qualifying referral is generally a new user who signs up through your unique referral
          link or valid affiliate promotion code and is durably attributed to your affiliate account
          in TradeTraxs and Stripe checkout records.
        </p>
        <p>
          Commissions described below apply to qualifying <strong>TraxPro subscriptions purchased
          on the TradeTraxs website through Stripe</strong> by referred users. App Store (Apple)
          purchases are processed by Apple and are not part of the Stripe affiliate commission
          calculation described in these Affiliate Terms unless we state otherwise in the Service.
        </p>
        <p>
          Referred users may receive a one-time {AFFILIATE_DISCOUNT_PERCENT_OFF}% discount on their
          first qualifying Stripe invoice when they use an eligible affiliate promotion code, as
          configured in the Service. Discounts affect the commission base as described below.
        </p>
      </>
    ),
  },
  {
    id: "commissions",
    title: "Commissions",
    content: (
      <>
        <p>
          For each qualifying paid Stripe subscription invoice attributed to you, TradeTraxs records
          a commission equal to <strong>{COMMISSION_PERCENT}%</strong> of the invoice commission
          base. The commission base is derived from Stripe invoice amounts <strong>after
          discounts and before tax</strong> (not from list prices or tax-inclusive totals). Trial,
          void, unpaid, or $0 invoices do not generate commission.
        </p>
        <p>
          Commissions are tracked in your affiliate dashboard and related ledger records. Displayed
          balances and payout availability follow program logic in the Service (including reserved
          amounts for pending or approved payout requests).
        </p>
      </>
    ),
  },
  {
    id: "payouts",
    title: "Payout Threshold, Requests, and Stripe Connect",
    content: (
      <>
        <p>
          You may request a payout when your available balance meets the current minimum threshold
          of <strong>${MINIMUM_PAYOUT_USD} USD</strong> (or another amount shown in your dashboard
          if we update the program). You may have only one pending payout request at a time.
        </p>
        <p>
          Payouts are processed through <strong>Stripe Connect</strong>. You must complete Stripe
          Connect onboarding and provide accurate payout and tax information. TradeTraxs does not
          store your full bank account details; Stripe handles payout execution subject to
          Stripe&apos;s terms and verification requirements.
        </p>
        <p>
          Approved payouts may be fulfilled via Stripe transfers or other methods we specify in the
          Service or to you directly. Timing depends on review, fraud checks, and third-party
          processing.
        </p>
      </>
    ),
  },
  {
    id: "refunds-chargebacks",
    title: "Refunds, Chargebacks, and Adjustments",
    content: (
      <>
        <p>
          Commissions are recorded when qualifying Stripe invoices are paid. If a referred
          subscription payment is refunded, charged back, or reversed, TradeTraxs may adjust,
          withhold, or reverse associated commissions and payout balances to reflect the reversal.
        </p>
        <p>
          We may also adjust balances to correct errors, duplicate attribution, or policy violations.
        </p>
      </>
    ),
  },
  {
    id: "prohibited-conduct",
    title: "Prohibited Conduct",
    content: (
      <>
        <p>You must not:</p>
        <ul>
          <li>
            Refer yourself or create accounts to earn commissions on your own subscriptions
            (self-referrals);
          </li>
          <li>Use spam, unsolicited bulk messaging, or deceptive funnels to drive sign-ups;</li>
          <li>
            Make misleading claims about TradeTraxs, guaranteed income, or trading performance;
          </li>
          <li>
            Bid on or misuse TradeTraxs trademarks or branding in paid search or ads without our
            written permission;
          </li>
          <li>Manipulate attribution, cookies, or checkout flows to inflate commissions; or</li>
          <li>Violate our Terms, Acceptable Use Policy, or Community Guidelines.</li>
        </ul>
        <p>
          See also our <Link href="/creator-guidelines">Creator Guidelines</Link> where applicable.
        </p>
      </>
    ),
  },
  {
    id: "ftc-disclosures",
    title: "Advertising Disclosures",
    content: (
      <>
        <p>
          When you promote TradeTraxs in content where you earn commissions, you must clearly and
          conspicuously disclose your material connection to TradeTraxs (for example, &quot;affiliate
          link&quot; or &quot;I may earn a commission&quot;) in a manner that complies with FTC
          endorsement guidelines and other applicable advertising laws.
        </p>
      </>
    ),
  },
  {
    id: "taxes",
    title: "Taxes",
    content: (
      <>
        <p>
          You are responsible for reporting and paying taxes on commission income you receive, as
          required by applicable law. Stripe Connect onboarding may require tax forms (such as W-9 or
          W-8) before payouts are enabled.
        </p>
      </>
    ),
  },
  {
    id: "termination",
    title: "Suspension, Termination, and Forfeiture",
    content: (
      <>
        <p>
          We may suspend or terminate your affiliate status, withhold payouts, or forfeit accrued
          commissions if we reasonably believe you violated these Affiliate Terms, our Terms, or
          applicable law, or if required for fraud prevention, chargebacks, or legal compliance.
        </p>
        <p>
          You may stop participating at any time, but accrued obligations (including pending review
          of payout requests and reversal adjustments) survive termination.
        </p>
      </>
    ),
  },
  {
    id: "changes",
    title: "Changes to the Program",
    content: (
      <>
        <p>
          We may modify commission rates, discount offers, minimum payout thresholds, eligibility
          rules, or these Affiliate Terms. Material changes will be posted on this page with an
          updated &quot;Last updated&quot; date. Continued participation after changes take effect
          constitutes acceptance, subject to applicable law.
        </p>
      </>
    ),
  },
  {
    id: "contact",
    title: "Contact",
    content: (
      <>
        <p>
          Questions about the Affiliate Program or these Affiliate Terms:{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
        </p>
      </>
    ),
  },
]
