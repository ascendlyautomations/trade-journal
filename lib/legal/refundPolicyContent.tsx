import Link from "next/link"
import type { LegalSection } from "@/app/components/LegalDocumentLayout"
import { SUPPORT_EMAIL } from "@/lib/contactEmails"
import { LEGAL_ENTITY_NAME } from "@/lib/legal/contact"

export const REFUND_POLICY_SECTIONS: LegalSection[] = [
  {
    id: "overview",
    title: "Overview",
    content: (
      <>
        <p>
          This Refund Policy explains how {LEGAL_ENTITY_NAME} (&quot;TradeTraxs,&quot; &quot;we,&quot;
          &quot;us,&quot; or &quot;our&quot;) handles subscription billing and refunds for paid
          TradeTraxs plans (including TraxPro).
        </p>
        <p>
          This policy should be read together with our{" "}
          <Link href="/terms">Terms of Service</Link>. If you have questions, contact us at{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>.
        </p>
      </>
    ),
  },
  {
    id: "billing",
    title: "Subscription Billing",
    content: (
      <>
        <p>
          TradeTraxs subscriptions are billed in advance on a recurring basis according to the plan
          you select (for example, monthly, six-month, or yearly).
        </p>
        <p>
          Because users receive immediate access to premium features upon subscribing,{" "}
          <strong>
            all subscription purchases are final and non-refundable
          </strong>
          , except where required by applicable law.
        </p>
      </>
    ),
  },
  {
    id: "cancellation",
    title: "Cancellation",
    content: (
      <>
        <p>
          If you cancel your subscription, you will continue to have access through the end of your
          current billing period. Your subscription will not renew after that period.
        </p>
        <p>
          Deleting your account does not automatically cancel your subscription. Cancel billing
          through the Stripe Customer Portal or the cancellation method provided in the Service if
          you wish to stop future charges.
        </p>
      </>
    ),
  },
  {
    id: "billing-errors",
    title: "Billing Errors and Chargebacks",
    content: (
      <>
        <p>
          If you believe you were charged in error, please contact TradeTraxs Support at{" "}
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a> before initiating a chargeback so
          we can investigate and resolve the issue.
        </p>
      </>
    ),
  },
  {
    id: "discretionary-refunds",
    title: "Discretionary Refunds",
    content: (
      <>
        <p>
          TradeTraxs reserves the right to issue refunds at its sole discretion in exceptional
          circumstances.
        </p>
      </>
    ),
  },
]
