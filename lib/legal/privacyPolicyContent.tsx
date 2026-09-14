import Link from "next/link"
import type { LegalSection } from "@/app/components/LegalDocumentLayout"
import { SUPPORT_EMAIL } from "@/lib/contactEmails"
import { LEGAL_ENTITY_NAME } from "@/lib/legal/contact"
import { SITE_URL } from "@/lib/site"

export const PRIVACY_POLICY_SECTIONS: LegalSection[] = [
  {
    id: "introduction",
    title: "Introduction",
    content: (
      <>
        <p>
          {LEGAL_ENTITY_NAME}{" "}
          (&quot;TradeTraxs,&quot; &quot;we,&quot; &quot;us,&quot; or &quot;our&quot;) operates a
          trading journal and social trading platform at{" "}
          <a href={SITE_URL}>{SITE_URL}</a>, including our website and native mobile applications
          (such as the TradeTraxs iOS app). This Privacy Policy explains how we collect, use,
          disclose, and protect information when you use our website, applications, and related
          services (collectively, the &quot;Service&quot;).
        </p>
        <p>
          TradeTraxs is <strong>not a broker</strong>, does not execute trades, and does not
          provide investment, financial, tax, or legal advice. By using the Service, you agree to
          this Privacy Policy. If you do not agree, please do not use the Service.
        </p>
      </>
    ),
  },
  {
    id: "data-we-collect",
    title: "Information We Collect",
    content: (
      <>
        <p>We collect information in the following categories:</p>
        <ul>
          <li>
            <strong>Account information</strong>, email address, password (stored in hashed form
            by our authentication provider), username, display name, profile details, avatar,
            privacy settings, subscription status, and referral or affiliate identifiers you
            provide or that are assigned to you.
          </li>
          <li>
            <strong>Trading data</strong>, trades you log or import (including tickers, dates,
            profit and loss, direction, session, strategy notes, account labels, screenshots, and
            CSV import files); when you connect a supported broker or trading platform,
            authorized data from that connection (such as broker or platform user identifiers,
            trading account identifiers, orders, positions, executions or fills, transaction or
            trading history, balances or related account metadata, and information derived from
            the foregoing for journaling and analytics); dashboard preferences; and analytics
            derived from your trading activity within the Service.
          </li>
          <li>
            <strong>User-generated content</strong>, posts, clips, comments, likes, direct messages,
            Trade Room messages, photos and videos you upload, voice or audio messages where
            supported, stories, achievements, content reports, support tickets, feedback, bug
            reports, and any content you choose to make public or share with other users.
          </li>
          <li>
            <strong>Social and community data</strong>, followers, follow requests, room
            memberships, invites, notifications, and interaction history with other users.
          </li>
          <li>
            <strong>Payment and subscription information</strong>, subscription and billing
            metadata processed by Stripe on the web (such as customer ID, plan, payment status, and
            transaction records) and, on iOS, verified App Store subscription metadata (such as
            product ID, transaction identifiers, renewal/expiration status, and environment)
            synchronized to your TradeTraxs account. We do not store full payment card numbers on
            our servers, and the native iOS app does not collect or process payment card details.
          </li>
          <li>
            <strong>Push notification data</strong>, Apple Push Notification service (APNs) device
            tokens, optional installation identifiers used to manage token rotation on a device,
            platform, app version, and notification preference settings associated with your account.
          </li>
          <li>
            <strong>Technical and usage data</strong>, IP address, browser type, device
            information, log data, pages viewed, feature usage, in-app search queries and results
            metadata needed to operate search, performance metrics, and similar diagnostic
            information collected through hosting and analytics tools on the website. The native iOS
            app does not use the App Tracking Transparency framework, does not collect IDFA for
            advertising, and does not include third-party advertising or cross-app tracking SDKs;
            server logs may still record operational metadata when the app calls our backend.
          </li>
          <li>
            <strong>Communications</strong>, messages you send to us (support, feedback, legal
            inquiries) and related metadata.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: "account-information",
    title: "Account Information",
    content: (
      <>
        <p>
          When you create an account, we collect the information needed to authenticate you and
          operate your profile. You may sign up with email and password or, where enabled, third-party
          sign-in such as Google.
        </p>
        <p>
          You control certain profile settings, including whether your profile is public or private.
          Private profiles limit visibility of your trading activity and posts to approved
          followers as described in the Service. You are responsible for keeping your login
          credentials confidential.
        </p>
      </>
    ),
  },
  {
    id: "trading-data",
    title: "Trading Data",
    content: (
      <>
        <p>
          TradeTraxs is designed for journaling, performance tracking, and community sharing. You
          may enter trades manually, upload CSV files from other platforms, connect supported
          broker or trading platform integrations where available, attach screenshots, and choose
          whether individual trades or posts are public or private.
        </p>
        <p>
          When you voluntarily connect a supported broker or trading platform (such as Tradovate),
          we may receive and process data you authorize through that integration, including broker
          or platform user identifiers, trading account identifiers and account information, orders,
          positions, executions or fills, transaction or trading history, balances or related account
          metadata when authorized, and data derived from the above to power TradeTraxs journaling,
          dashboards, calendars, analytics, reporting, and related features. We use this information
          to connect your broker account, import or synchronize trading activity, create and update
          journal records, provide product functionality, and maintain or troubleshoot the
          authorized integration.
        </p>
        <p>
          Supported broker connections use authorization mechanisms such as OAuth where offered.
          You authenticate with the broker or platform; TradeTraxs does not ask you to provide your
          Tradovate password for the OAuth-based Tradovate integration and does not need or store
          that password through that flow. To maintain an authorized connection, we may securely
          store authorization tokens or similar credentials server-side. Access is limited to
          permissions you grant through the integration. You may disconnect supported broker
          integrations where the Service provides that control. Disconnecting stops future
          synchronization but does not automatically delete trading data already imported into
          TradeTraxs unless you delete it through available TradeTraxs controls. The initial
          Tradovate integration is intended for journal and data synchronization; it is not
          intended to authorize TradeTraxs to place trades on your behalf.
        </p>
        <p>
          Unless you share content publicly or with other users through the Service, your private
          trade notes and non-public trades are intended to remain visible only to you and our
          systems as needed to provide the Service. We use commercially reasonable safeguards, but
          no system is perfectly secure; you should not treat the Service as a guaranteed private
          vault. CSV files you upload may be stored to complete import and, if you submit them for
          format support, to improve import compatibility.
        </p>
        <p>
          <strong>Important:</strong> Do not upload broker account passwords, API secrets, or other
          login credentials you type or paste into TradeTraxs (for example in support messages,
          posts, or CSV attachments). TradeTraxs does not need your broker password to operate
          manual journaling or CSV import, and the OAuth-based Tradovate connection does not use
          your Tradovate password. That is different from authorization tokens or similar
          credentials stored securely on our servers solely to maintain an integration you
          authorized—we do not treat those server-side tokens as something you should manually
          submit or share.
        </p>
      </>
    ),
  },
  {
    id: "user-generated-content",
    title: "User-Generated Content",
    content: (
      <>
        <p>
          Content you publish, including feed posts, clips, trade shares, comments, profile posts,
          photos, videos, voice messages, direct messages, and Trade Room participation, may be
          visible to other users according to your settings and the feature you use.
        </p>
        <p>
          Public content may be displayed on leaderboards, explore pages, or other public areas of
          the Service according to product features and your settings. You may delete or edit
          certain content where the Service provides those controls, but copies or references may
          persist in backups, logs, or other users&apos; devices for a period of time.
        </p>
      </>
    ),
  },
  {
    id: "analytics",
    title: "Analytics and Performance Monitoring",
    content: (
      <>
        <p>We use analytics and performance tools to understand how the Service is used and to improve reliability, including:</p>
        <ul>
          <li>
            <strong>Vercel Analytics</strong>, aggregated usage and traffic metrics.
          </li>
          <li>
            <strong>Vercel Speed Insights</strong>, performance and Core Web Vitals data.
          </li>
          <li>
            <strong>Server and application logs</strong>, error reporting, security monitoring, and
            operational diagnostics through our hosting infrastructure.
          </li>
        </ul>
        <p>
          These tools may collect pseudonymous identifiers, page views, referrers, device/browser
          characteristics, and performance timings. We use this data in aggregate to improve the
          Service, not to sell your personal trading journal as a standalone product.
        </p>
      </>
    ),
  },
  {
    id: "cookies",
    title: "Cookies and Similar Technologies",
    content: (
      <>
        <p>
          We use cookies, local storage, and similar technologies to keep you signed in, remember
          preferences, protect against abuse, and measure site performance.
        </p>
        <ul>
          <li>
            <strong>Essential cookies/storage</strong>, required for authentication, security, and
            core functionality (including Supabase session management).
          </li>
          <li>
            <strong>Analytics cookies/scripts</strong>, used by Vercel Analytics and Speed Insights
            as described above.
          </li>
        </ul>
        <p>
          You can control cookies through your browser settings. Disabling essential cookies may
          prevent you from using parts of the Service.
        </p>
      </>
    ),
  },
  {
    id: "mobile-applications",
    title: "Mobile Applications",
    content: (
      <>
        <p>
          When you use the TradeTraxs native iOS app, the app communicates with the same TradeTraxs
          backend services used by the website. Data you create or upload in the app (such as
          trades, posts, messages, media, and profile information) is stored in our Supabase-backed
          infrastructure and associated with your account.
        </p>
        <p>
          The iOS app may request device permissions (camera, microphone, photo library, and push
          notifications) only in context when you use features that need them. You can deny optional
          permissions and continue using parts of the Service that do not require them.
        </p>
        <p>
          TraxPro subscriptions purchased through the Apple App Store are verified server-side using
          Apple-provided transaction information. Apple processes payment; we store subscription
          entitlement metadata needed to provide TraxPro features across platforms.
        </p>
      </>
    ),
  },
  {
    id: "ai-processing",
    title: "AI Features and Third-Party AI Processing",
    content: (
      <>
        <p>
          Certain TraxPro AI features send data from your account to TradeTraxs servers, which may
          forward relevant content to third-party AI providers (including OpenAI) to generate
          responses. OpenAI API keys and model calls are server-side only; they are not embedded in
          the native app.
        </p>
        <ul>
          <li>
            <strong>Trade AI</strong>, trade fields you submit (such as symbol, direction, prices,
            times, notes, psychology tags, and related journal context), prior in-conversation
            messages, and optional trade screenshot images when available.
          </li>
          <li>
            <strong>Psychology Coach</strong>, structured analytics facts computed for your account
            (such as win rate, expectancy, pattern summaries, and sample sizes) plus your follow-up
            questions. Daily check-in free-text notes are not included in Psychology Coach requests.
          </li>
          <li>
            <strong>Screenshot import / extraction</strong>, broker screenshot images you choose to
            submit for structured trade extraction.
          </li>
        </ul>
        <p>
          AI output may be inaccurate, incomplete, delayed, or incorrect and is for educational
          purposes only, not financial advice. Do not submit information you do not want processed
          for that purpose.
        </p>
      </>
    ),
  },
  {
    id: "third-parties",
    title: "Third-Party Services",
    content: (
      <>
        <p>
          We rely on trusted service providers to operate TradeTraxs. They process data on our
          behalf according to their terms and our instructions. Key providers include:
        </p>
        <ul>
          <li>
            <strong>Supabase</strong>, authentication, database, storage, and backend
            infrastructure.
          </li>
          <li>
            <strong>Stripe</strong>, web subscription billing and affiliate/payout processing where
            applicable.
          </li>
          <li>
            <strong>Apple</strong>, App Store subscription purchase processing and subscription
            management for TraxPro on iOS.
          </li>
          <li>
            <strong>Vercel</strong>, hosting, deployment, analytics, and speed insights (website).
          </li>
          <li>
            <strong>Google</strong>, optional sign-in (Google OAuth) and Google Workspace for
            business email and operations.
          </li>
          <li>
            <strong>AI service providers</strong>, including OpenAI when you use AI features
            described above.
          </li>
          <li>
            <strong>Brokers and trading platforms</strong>, such as Tradovate when you choose to
            connect an account. Those providers authenticate you and may transmit trading data to
            TradeTraxs according to their terms, APIs, and the permissions you grant. Listing a
            provider here does not imply that the provider endorses TradeTraxs.
          </li>
        </ul>
        <p>
          These providers may process data in the United States and other countries. Their privacy
          policies govern their direct collection where applicable.
        </p>
      </>
    ),
  },
  {
    id: "how-we-use",
    title: "How We Use Information",
    content: (
      <>
        <p>We use collected information to:</p>
        <ul>
          <li>Provide, maintain, and improve the Service;</li>
          <li>Authenticate users and secure accounts;</li>
          <li>Process subscriptions, referrals, and affiliate payouts;</li>
          <li>Enable social features, messaging, notifications, and Trade Rooms;</li>
          <li>Generate AI-assisted trade analysis when you request it;</li>
          <li>
            Connect, import, and synchronize authorized broker or platform data and maintain those
            integrations;
          </li>
          <li>Respond to support, feedback, and legal requests;</li>
          <li>Detect abuse, fraud, and violations of our Terms;</li>
          <li>Comply with legal obligations; and</li>
          <li>Send service-related communications (you may opt out of non-essential marketing where offered).</li>
        </ul>
      </>
    ),
  },
  {
    id: "sharing",
    title: "How We Share Information",
    content: (
      <>
        <p>We may share information:</p>
        <ul>
          <li>
            <strong>With other users</strong>, according to your sharing settings and public profile
            choices.
          </li>
          <li>
            <strong>With service providers</strong>, listed under Third-Party Services.
          </li>
          <li>
            <strong>For legal reasons</strong>, if required by law, subpoena, or to protect rights,
            safety, and integrity of the Service.
          </li>
          <li>
            <strong>Business transfers</strong>, in connection with a merger, acquisition, or sale
            of assets, subject to continued protection consistent with this policy.
          </li>
        </ul>
        <p>We do not sell your personal information for money.</p>
      </>
    ),
  },
  {
    id: "retention",
    title: "Data Retention",
    content: (
      <>
        <p>
          We retain information for as long as your account is active or as needed to provide the
          Service, comply with legal obligations, resolve disputes, and enforce our agreements.
        </p>
        <p>
          When you delete your account (where available), we delete or anonymize personal
          information within a reasonable period, except where retention is required by law or
          legitimate business needs (such as billing records, abuse prevention, or backup systems
          that purge on a rolling schedule).
        </p>
        <p>
          Account deletion removes or cleans up most account-linked content, including trades,
          posts, clips, profile data, storage files, push notification tokens, and Apple
          subscription entitlement records stored for your account. Direct messages and Trade Room
          messages you sent may be <strong>anonymized</strong> (sender identity removed) rather
          than deleted from other participants&apos; threads so conversation history remains
          coherent for recipients. Content reports, moderation records, and certain billing or
          fraud-prevention records may be retained as needed for safety, legal, or accounting
          obligations. Deleting your TradeTraxs account does <strong>not</strong> automatically
          cancel an Apple App Store subscription.
        </p>
      </>
    ),
  },
  {
    id: "security",
    title: "Security",
    content: (
      <>
        <p>
          We implement commercially reasonable administrative, technical, and organizational
          measures designed to protect information, including encryption in transit (HTTPS), access
          controls, and authentication practices through Supabase.
        </p>
        <p>
          No method of transmission or storage is completely secure. You use the Service at your own
          risk and should use a strong, unique password and protect your devices.
        </p>
      </>
    ),
  },
  {
    id: "your-rights",
    title: "Your Rights and Choices",
    content: (
      <>
        <p>Depending on your location, you may have rights to:</p>
        <ul>
          <li>Access, correct, or delete personal information we hold about you;</li>
          <li>Export your data where the Service provides an export feature;</li>
          <li>Object to or restrict certain processing;</li>
          <li>Withdraw consent where processing is consent-based; and</li>
          <li>Lodge a complaint with a supervisory authority.</li>
        </ul>
        <p>
          You can update profile and privacy settings in the Service. Web subscribers may manage
          Stripe billing through the Stripe Customer Portal where available. Apple App Store
          subscribers manage renewal and cancellation in iOS Settings → Apple ID → Subscriptions.
          Contact us to exercise privacy rights. We may verify your identity before responding.
        </p>
        <p>
          California residents may have additional rights under the CCPA/CPRA. EEA/UK users may have
          rights under GDPR. We aim to honor applicable legal requirements within reasonable
          timeframes.
        </p>
      </>
    ),
  },
  {
    id: "children",
    title: "Age Requirement",
    content: (
      <p>
        You must be at least <strong>18 years old</strong> to use TradeTraxs. The Service is not
        directed to anyone under 18. We do not knowingly collect personal information from anyone
        under 18. If you believe someone under 18 has provided us information, contact us and we
        will take appropriate steps to delete it.
      </p>
    ),
  },
  {
    id: "international",
    title: "International Users",
    content: (
      <p>
        {LEGAL_ENTITY_NAME} operates TradeTraxs from the United States. If you access the Service
        from other regions, your information may be transferred to, stored, and processed in the
        United States and other countries where we or our providers operate, which may have different
        data protection laws than your home country.
      </p>
    ),
  },
  {
    id: "changes",
    title: "Changes to This Policy",
    content: (
      <p>
        We may update this Privacy Policy from time to time. We will post the revised policy on this
        page and update the &quot;Last updated&quot; date. Material changes may be communicated
        through the Service or by email where appropriate. Continued use after changes become
        effective constitutes acceptance of the updated policy.
      </p>
    ),
  },
  {
    id: "contact",
    title: "Contact Us",
    content: (
      <>
        <p>
          For privacy questions, data requests, or concerns about this policy, contact us at:
        </p>
        <p>
          <strong>{LEGAL_ENTITY_NAME}</strong>
          <br />
          <strong>Email:</strong>{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
        </p>
        <p>
          You may also use our{" "}
          <Link href="/support">Support</Link> page for account-related requests.
        </p>
      </>
    ),
  },
]
