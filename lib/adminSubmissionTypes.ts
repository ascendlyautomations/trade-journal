export type AdminSubmissionType =
  | "bug_report"
  | "feature_request"
  | "support_ticket"
  | "csv_support_request"
  | "feedback_submission"
  | "affiliate_application"
  | "user_review"
  | "contact_general"
  | "contact_billing"
  | "contact_partnership"
  | "contact_business"
  | "contact_faq"

export const ADMIN_SUBMISSION_EMAIL_SUBJECTS: Record<AdminSubmissionType, string> = {
  bug_report: "[TradeTraxs] New Bug Report",
  feature_request: "[TradeTraxs] New Feature Request",
  support_ticket: "[TradeTraxs] New Support Request",
  csv_support_request: "[TradeTraxs] New CSV Support Request",
  feedback_submission: "[TradeTraxs] New Feedback Submission",
  affiliate_application: "New Affiliate Application",
  user_review: "[Review] New Beta Review Submitted",
  contact_general: "[General] Question About TradeTraxs",
  contact_billing: "[Billing] Subscription Question",
  contact_partnership: "[Partnership] Partnership Inquiry",
  contact_business: "[Business] Business Inquiry",
  contact_faq: "FAQ Question",
}

export const ADMIN_SUBMISSION_ADMIN_PATHS: Record<AdminSubmissionType, string> = {
  bug_report: "/admin/bug-reports",
  feature_request: "/admin/feature-requests",
  support_ticket: "/admin/support",
  csv_support_request: "/admin/csv-support",
  feedback_submission: "/admin/feedback",
  affiliate_application: "/admin/affiliates",
  user_review: "/admin/reviews",
  contact_general: "/contact",
  contact_billing: "/contact",
  contact_partnership: "/contact",
  contact_business: "/contact",
  contact_faq: "/faq",
}

export const ADMIN_SUBMISSION_LABELS: Record<AdminSubmissionType, string> = {
  bug_report: "Bug Report",
  feature_request: "Feature Request",
  support_ticket: "Support Request",
  csv_support_request: "CSV Support Request",
  feedback_submission: "Feedback Submission",
  affiliate_application: "Affiliate Application",
  user_review: "User Review",
  contact_general: "Public Contact, General",
  contact_billing: "Public Contact, Billing",
  contact_partnership: "Public Contact, Partnership",
  contact_business: "Public Contact, Business",
  contact_faq: "Public Contact, FAQ",
}

export function isPublicContactSubmissionType(
  type: AdminSubmissionType
): type is
  | "contact_general"
  | "contact_billing"
  | "contact_partnership"
  | "contact_business"
  | "contact_faq" {
  return type.startsWith("contact_")
}
