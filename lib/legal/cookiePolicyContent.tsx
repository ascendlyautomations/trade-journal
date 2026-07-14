import Link from "next/link"
import type { LegalSection } from "@/app/components/LegalDocumentLayout"
import { SUPPORT_EMAIL } from "@/lib/contactEmails"
import { LEGAL_ENTITY_NAME } from "@/lib/legal/contact"
import { SITE_URL } from "@/lib/site"

export const COOKIE_POLICY_SECTIONS: LegalSection[] = [
  {
    id: "introduction",
    title: "Introduction",
    content: (
      <>
        <p>
          This Cookie Policy explains how {LEGAL_ENTITY_NAME} (&quot;TradeTraxs,&quot; &quot;we,&quot;
          &quot;us,&quot; or &quot;our&quot;) uses cookies and similar technologies when you visit{" "}
          <a href={SITE_URL}>{SITE_URL}</a> or use our applications and related services
          (collectively, the &quot;Service&quot;).
        </p>
        <p>
          This policy should be read together with our{" "}
          <Link href="/privacy">Privacy Policy</Link>. If you have questions, contact us at{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
        </p>
      </>
    ),
  },
  {
    id: "what-are-cookies",
    title: "What Are Cookies?",
    content: (
      <>
        <p>
          Cookies are small text files stored on your device by your browser. Similar technologies
          include local storage, session storage, and pixels or scripts that remember information
          about your visit or device.
        </p>
        <p>
          Some technologies are set by TradeTraxs directly. Others may be set by trusted providers
          we use to operate authentication, payments, hosting, or analytics.
        </p>
      </>
    ),
  },
  {
    id: "why-we-use-cookies",
    title: "Why TradeTraxs Uses Cookies and Similar Technologies",
    content: (
      <>
        <p>We use these technologies to:</p>
        <ul>
          <li>Keep you securely signed in and protect your account</li>
          <li>Operate core platform features and prevent abuse</li>
          <li>Process subscriptions and checkout flows through Stripe</li>
          <li>Remember preferences and improve performance</li>
          <li>Understand how the Service is used so we can improve it</li>
        </ul>
        <p>
          We do not use cookies for purposes we have not described in this policy or our Privacy
          Policy.
        </p>
      </>
    ),
  },
  {
    id: "authentication",
    title: "Authentication Cookies and Storage (Supabase)",
    content: (
      <>
        <p>
          TradeTraxs uses Supabase for authentication. Supabase and our application may store
          session-related data in cookies and/or browser storage (such as local storage) to keep you
          signed in, refresh your session, and secure account access.
        </p>
        <p>
          These technologies are <strong>essential</strong> to the Service. Without them, you
          cannot sign in or use authenticated features.
        </p>
      </>
    ),
  },
  {
    id: "security",
    title: "Security Cookies and Storage",
    content: (
      <>
        <p>
          We use essential cookies and storage to help protect the Service and our users, including
          measures that support abuse prevention, session integrity, and secure routing for
          authenticated requests.
        </p>
        <p>
          Disabling or clearing these technologies may sign you out, block access to protected
          pages, or prevent certain security features from working correctly.
        </p>
      </>
    ),
  },
  {
    id: "session",
    title: "Session Cookies and Storage",
    content: (
      <>
        <p>
          Session-related technologies allow TradeTraxs to maintain your active session while you
          use the platform, remember in-progress flows (such as onboarding or checkout return paths),
          and restore state during your visit.
        </p>
        <p>
          Some session data is stored for the duration of your browser session; other data may
          persist until you sign out or clear your browser storage.
        </p>
      </>
    ),
  },
  {
    id: "stripe",
    title: "Stripe Checkout and Payment Session Cookies",
    content: (
      <>
        <p>
          When you subscribe to TradeTraxs Pro or complete billing actions, Stripe may set cookies
          or use similar technologies to process payments securely, prevent fraud, and manage
          checkout or customer portal sessions.
        </p>
        <p>
          We do not store full payment card numbers on TradeTraxs servers. Stripe&apos;s use of
          cookies is governed by Stripe&apos;s own policies when you interact with their checkout
          or billing flows.
        </p>
      </>
    ),
  },
  {
    id: "preferences",
    title: "Preference Cookies and Storage",
    content: (
      <>
        <p>
          TradeTraxs may store preferences in browser storage (such as local storage or session
          storage) to remember settings, UI state, referral codes you arrived with, cookie consent
          choices, and similar non-essential convenience features that improve your experience.
        </p>
        <p>
          These preferences are generally tied to your browser and device unless otherwise
          described in our Privacy Policy.
        </p>
      </>
    ),
  },
  {
    id: "analytics",
    title: "Analytics Cookies and Scripts",
    content: (
      <>
        <p>
          TradeTraxs may use product analytics tools such as Vercel Analytics and Vercel Speed
          Insights to understand traffic, performance, and feature usage. These tools may use
          cookies, scripts, or similar technologies.
        </p>
        <p>
          Where required, we ask for your consent before treating analytics as enabled. If you
          choose <strong>Essential Only</strong> in our cookie banner, we record that analytics
          preferences are disabled even if some analytics scripts are still loaded for core
          operation. We use your stored preference to guide future analytics implementations.
        </p>
      </>
    ),
  },
  {
    id: "managing-cookies",
    title: "How to Clear or Control Cookies",
    content: (
      <>
        <p>You can manage cookies and browser storage in several ways:</p>
        <ul>
          <li>
            Use our cookie banner to choose <strong>Accept All</strong> or{" "}
            <strong>Essential Only</strong>
          </li>
          <li>Clear cookies and site data through your browser settings</li>
          <li>Use private browsing modes that limit persistent storage</li>
          <li>Block third-party cookies in your browser, where supported</li>
        </ul>
        <p>
          Clearing essential cookies or storage will sign you out and may prevent subscriptions,
          messaging, journaling, and other core features from working until you sign in again.
        </p>
      </>
    ),
  },
  {
    id: "contact",
    title: "Contact Us",
    content: (
      <>
        <p>
          For questions about this Cookie Policy or our use of cookies and similar technologies,
          contact {LEGAL_ENTITY_NAME} at{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
        </p>
      </>
    ),
  },
]
