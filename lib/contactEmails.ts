/** Canonical TradeTraxs contact email addresses — update here only. */

export const TRADETRAXS_DOMAIN = "tradetraxs.com" as const

/**
 * Primary inbox for support, help, contact, feedback, bug reports, feature
 * requests, CSV support, and general inquiries.
 */
export const SUPPORT_EMAIL = `support@${TRADETRAXS_DOMAIN}` as const

/** Copyright and DMCA notices (takedowns and counter-notifications). */
export const COPYRIGHT_EMAIL = `copyright@${TRADETRAXS_DOMAIN}` as const

/**
 * Default Resend "from" address for outbound admin notification emails.
 * Override in production with `ADMIN_NOTIFY_FROM_EMAIL` when configured.
 */
export const NOTIFICATIONS_FROM_EMAIL =
  `TradeTraxs Notifications <notifications@${TRADETRAXS_DOMAIN}>` as const

export function supportMailtoHref(): string {
  return `mailto:${SUPPORT_EMAIL}`
}

export function copyrightMailtoHref(): string {
  return `mailto:${COPYRIGHT_EMAIL}`
}
