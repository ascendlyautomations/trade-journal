import Link from "next/link"
import type { LegalSection } from "@/app/components/LegalDocumentLayout"
import {
  LEGAL_COPYRIGHT_EMAIL,
  LEGAL_ENTITY_NAME,
  LEGAL_SUPPORT_EMAIL,
} from "@/lib/legal/contact"
import { SITE_URL } from "@/lib/site"

export const COPYRIGHT_DMCA_SECTIONS: LegalSection[] = [
  {
    id: "overview",
    title: "Overview",
    content: (
      <>
        <p>
          {LEGAL_ENTITY_NAME} respects intellectual property rights and expects users of TradeTraxs
          to do the same. This page explains how copyright owners can report allegedly infringing
          content on our platform and how users may respond if their content is removed.
        </p>
        <p>
          TradeTraxs hosts user-generated content, including trade screenshots, chart images,
          videos, reels, posts, comments, and messages. We respond to valid copyright complaints and
          may remove or restrict access to material that infringes the rights of others.
        </p>
        <p>
          This policy is provided for informational purposes and does not constitute legal advice.
          If you are unsure about your rights or obligations, consult qualified counsel.
        </p>
      </>
    ),
  },
  {
    id: "reporting",
    title: "How to Report Infringing Content",
    content: (
      <>
        <p>
          If you believe content on TradeTraxs infringes your copyright, send a written notice to
          our designated copyright agent:
        </p>
        <p>
          <strong>Email:</strong>{" "}
          <a href={`mailto:${LEGAL_COPYRIGHT_EMAIL}`}>{LEGAL_COPYRIGHT_EMAIL}</a>
        </p>
        <p>
          Please include the information below so we can review your request promptly. Incomplete
          notices may delay processing.
        </p>
      </>
    ),
  },
  {
    id: "takedown-requirements",
    title: "Information Required in a Takedown Request",
    content: (
      <>
        <p>Your notice should include:</p>
        <ul>
          <li>
            Your name and contact information (email and, if available, phone number and mailing
            address).
          </li>
          <li>
            Identification of the copyrighted work you believe has been infringed, or a
            representative list if multiple works are involved.
          </li>
          <li>
            Identification of the material on TradeTraxs that you claim is infringing, with enough
            detail for us to locate it (for example, profile URL, post link, trade ID, message
            context, or screenshots).
          </li>
          <li>
            A statement that you have a good-faith belief that use of the material is not
            authorized by the copyright owner, its agent, or the law.
          </li>
          <li>
            A statement, under penalty of perjury, that the information in your notice is accurate
            and that you are the copyright owner or authorized to act on the owner&apos;s behalf.
          </li>
          <li>Your physical or electronic signature.</li>
        </ul>
        <p>
          <strong>Knowingly false claims:</strong> Submitting a false or misleading infringement
          notice may have legal consequences, including liability for damages under applicable law
          (such as 17 U.S.C. § 512(f) in the United States).
        </p>
      </>
    ),
  },
  {
    id: "review-process",
    title: "Our Review Process",
    content: (
      <>
        <p>When we receive a complete copyright notice, we typically:</p>
        <ul>
          <li>Review the notice for required information;</li>
          <li>Locate the reported content on TradeTraxs;</li>
          <li>
            Remove or disable access to the material, or restrict the account, where appropriate;
          </li>
          <li>
            Notify the user who posted the content when practicable, including information about
            counter-notification options where applicable; and
          </li>
          <li>Document the action taken in accordance with our policies.</li>
        </ul>
        <p>
          We aim to process valid notices in a reasonable timeframe. Complex or incomplete reports
          may take longer. We are not obligated to adjudicate disputes between users and rights
          holders.
        </p>
      </>
    ),
  },
  {
    id: "counter-notification",
    title: "Counter-Notifications",
    content: (
      <>
        <p>
          If your content was removed or disabled because of a copyright notice and you believe the
          removal was a mistake or misidentification, you may submit a counter-notification to{" "}
          <a href={`mailto:${LEGAL_COPYRIGHT_EMAIL}`}>{LEGAL_COPYRIGHT_EMAIL}</a>.
        </p>
        <p>Your counter-notification should include:</p>
        <ul>
          <li>Your name, address, telephone number, and email address;</li>
          <li>
            Identification of the material that was removed and the location where it appeared before
            removal;
          </li>
          <li>
            A statement under penalty of perjury that you have a good-faith belief the material was
            removed or disabled as a result of mistake or misidentification;
          </li>
          <li>
            A statement that you consent to the jurisdiction of the federal district court for the
            judicial district in which your address is located (or, if outside the United States,
            any judicial district in which {LEGAL_ENTITY_NAME} may be found), and that you will
            accept service of process from the person who submitted the original notice or their
            agent; and
          </li>
          <li>Your physical or electronic signature.</li>
        </ul>
        <p>
          If we receive a valid counter-notification, we may restore the material after a reasonable
          period unless the copyright owner informs us that they have filed a court action seeking to
          restrain the allegedly infringing activity.
        </p>
      </>
    ),
  },
  {
    id: "repeat-infringers",
    title: "Repeat Infringer Policy",
    content: (
      <>
        <p>
          In appropriate circumstances, {LEGAL_ENTITY_NAME} will terminate the accounts of users who
          are repeat infringers of copyright or other intellectual property rights. We may also
          suspend or restrict accounts after a single serious violation or a pattern of infringing
          behavior.
        </p>
        <p>
          Factors we may consider include the nature of the violation, prior warnings, counter-
          notifications, and the user&apos;s history on the Service.
        </p>
      </>
    ),
  },
  {
    id: "trademarks",
    title: "Trademark Concerns",
    content: (
      <p>
        This page focuses on copyright. If you believe content on TradeTraxs infringes your
        trademark, contact us at{" "}
        <a href={`mailto:${LEGAL_COPYRIGHT_EMAIL}`}>{LEGAL_COPYRIGHT_EMAIL}</a> with a description
        of the mark, how it is being used on the Service, and why you believe the use is
        unauthorized. We may remove content that violates trademark law or our{" "}
        <Link href="/acceptable-use">Acceptable Use Policy</Link>.
      </p>
    ),
  },
  {
    id: "other-issues",
    title: "Other Community Issues",
    content: (
      <p>
        For harassment, spam, or other community violations that are not primarily copyright
        matters, contact{" "}
        <a href={`mailto:${LEGAL_SUPPORT_EMAIL}`}>{LEGAL_SUPPORT_EMAIL}</a> or see our{" "}
        <Link href="/community-guidelines">Community Guidelines</Link> and{" "}
        <Link href="/terms">Terms of Service</Link>. Platform rules are published at{" "}
        <a href={SITE_URL}>{SITE_URL}</a>.
      </p>
    ),
  },
]
