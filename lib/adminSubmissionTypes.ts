export type AdminSubmissionType =
  | "bug_report"
  | "feature_request"
  | "support_ticket"
  | "csv_support_request"
  | "feedback_submission"
  | "affiliate_application"

export const ADMIN_SUBMISSION_EMAIL_SUBJECTS: Record<AdminSubmissionType, string> = {
  bug_report: "[TradeTraxs] New Bug Report",
  feature_request: "[TradeTraxs] New Feature Request",
  support_ticket: "[TradeTraxs] New Support Request",
  csv_support_request: "[TradeTraxs] New CSV Support Request",
  feedback_submission: "[TradeTraxs] New Feedback Submission",
  affiliate_application: "New Affiliate Application",
}

export const ADMIN_SUBMISSION_ADMIN_PATHS: Record<AdminSubmissionType, string> = {
  bug_report: "/admin/bug-reports",
  feature_request: "/admin/feature-requests",
  support_ticket: "/admin/support",
  csv_support_request: "/admin/csv-support",
  feedback_submission: "/admin/feedback",
  affiliate_application: "/admin/affiliates",
}

export const ADMIN_SUBMISSION_LABELS: Record<AdminSubmissionType, string> = {
  bug_report: "Bug Report",
  feature_request: "Feature Request",
  support_ticket: "Support Request",
  csv_support_request: "CSV Support Request",
  feedback_submission: "Feedback Submission",
  affiliate_application: "Affiliate Application",
}
