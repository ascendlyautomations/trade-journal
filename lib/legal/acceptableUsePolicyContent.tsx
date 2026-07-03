import Link from "next/link"
import type { LegalSection } from "@/app/components/LegalDocumentLayout"
import { LEGAL_CONTACT_EMAIL, LEGAL_ENTITY_NAME } from "@/lib/legal/contact"
import { SITE_URL } from "@/lib/site"

export const ACCEPTABLE_USE_POLICY_SECTIONS: LegalSection[] = [
  {
    id: "introduction",
    title: "Introduction",
    content: (
      <>
        <p>
          This Acceptable Use Policy (&quot;AUP&quot;) describes the rules for using{" "}
          {LEGAL_ENTITY_NAME}&apos;s trading journal and social platform at{" "}
          <a href={SITE_URL}>{SITE_URL}</a> (the &quot;Service&quot;).
        </p>
        <p>
          By using TradeTraxs, you agree to follow this AUP, our{" "}
          <Link href="/terms">Terms of Service</Link>, and our{" "}
          <Link href="/community-guidelines">Community Guidelines</Link>. Violations may result in
          content removal, account restrictions, or termination.
        </p>
      </>
    ),
  },
  {
    id: "illegal-activity",
    title: "No Illegal Activity",
    content: (
      <p>
        You may not use TradeTraxs for any unlawful purpose or in violation of applicable local,
        state, national, or international laws and regulations.
      </p>
    ),
  },
  {
    id: "harassment",
    title: "No Harassment",
    content: (
      <p>
        Harassment, bullying, threats, intimidation, stalking, and repeated unwanted contact are
        prohibited. This includes targeted abuse in comments, messages, Trade Rooms, and direct
        interactions.
      </p>
    ),
  },
  {
    id: "hate-speech",
    title: "No Hate Speech",
    content: (
      <p>
        Content that promotes hatred, violence, or discrimination against individuals or groups
        based on protected characteristics is not permitted on TradeTraxs.
      </p>
    ),
  },
  {
    id: "spam",
    title: "No Spam",
    content: (
      <p>
        Do not send unsolicited promotions, repetitive low-quality posts, referral spam, or bulk
        messages. Keep sharing relevant to trading, journaling, and community discussion.
      </p>
    ),
  },
  {
    id: "impersonation",
    title: "No Impersonation",
    content: (
      <p>
        Do not impersonate other traders, TradeTraxs staff, brands, or public figures. Do not
        misrepresent your identity, credentials, or affiliation.
      </p>
    ),
  },
  {
    id: "scams-fraud",
    title: "No Scams or Fraud",
    content: (
      <p>
        Scams, phishing, pyramid schemes, fake profit guarantees, pump-and-dump coordination, and
        other deceptive or fraudulent conduct are strictly prohibited.
      </p>
    ),
  },
  {
    id: "malicious-uploads",
    title: "No Malicious Uploads",
    content: (
      <p>
        Do not upload malware, exploit code, or files intended to harm users, systems, or third
        parties. Do not attempt to bypass security controls or access data you are not authorized
        to view.
      </p>
    ),
  },
  {
    id: "automated-abuse",
    title: "No Automated Abuse",
    content: (
      <p>
        Do not use bots, scripts, or automated tools to create accounts, post content, send
        messages, manipulate engagement, or otherwise abuse platform limits without authorization.
      </p>
    ),
  },
  {
    id: "scraping",
    title: "No Unauthorized Scraping",
    content: (
      <p>
        You may not scrape, crawl, harvest, or systematically collect data from TradeTraxs without
        our prior written permission, except as allowed by applicable law.
      </p>
    ),
  },
  {
    id: "copyright",
    title: "No Copyright Violations",
    content: (
      <p>
        Do not post content that infringes copyrights, trademarks, or other intellectual property
        rights. Only share material you have the right to use.
      </p>
    ),
  },
  {
    id: "respectful-community",
    title: "Respectful Community Behavior",
    content: (
      <>
        <p>
          TradeTraxs is built for traders who want to learn and improve together. Be honest about
          your results, respect privacy settings, and follow our{" "}
          <Link href="/community-guidelines">Community Guidelines</Link> and{" "}
          <Link href="/creator-guidelines">Creator Guidelines</Link> when sharing trades or content.
        </p>
        <p>
          Do not make misleading performance claims or present simulated results as live trading
          without clear disclosure.
        </p>
      </>
    ),
  },
  {
    id: "enforcement",
    title: "Enforcement Actions",
    content: (
      <>
        <p>
          We may investigate reported or suspected violations and take action we deem appropriate,
          including:
        </p>
        <ul>
          <li>Removing or restricting content</li>
          <li>Issuing warnings</li>
          <li>Temporarily limiting features</li>
          <li>Suspending or terminating accounts</li>
          <li>Reporting activity to law enforcement where required</li>
        </ul>
        <p>
          Enforcement decisions are made at our discretion to protect users and the integrity of the
          Service.
        </p>
      </>
    ),
  },
  {
    id: "contact",
    title: "Contact",
    content: (
      <p>
        To report abuse or ask questions about this policy, contact us at{" "}
        <a href={`mailto:${LEGAL_CONTACT_EMAIL}`}>{LEGAL_CONTACT_EMAIL}</a>.
      </p>
    ),
  },
]
