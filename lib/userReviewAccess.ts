/** Gate review submission — beta testers only today; expand here for all users later. */

export type UserReviewProfileGate = {
  is_beta_tester?: boolean | null
}

export function canSubmitUserReview(profile: UserReviewProfileGate | null | undefined): boolean {
  return profile?.is_beta_tester === true
}
