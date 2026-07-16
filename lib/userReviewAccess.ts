/** Gate review submission — any authenticated user (public launch). */

export type UserReviewProfileGate = {
  id?: string | null
  is_beta_tester?: boolean | null
}

/**
 * Reviews are open to all logged-in users. Profile presence is enough;
 * beta status is no longer required.
 */
export function canSubmitUserReview(
  profile: UserReviewProfileGate | null | undefined
): boolean {
  return profile != null
}
