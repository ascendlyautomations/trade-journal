export function getMembershipStatus(profile: any) {
  if (!profile) return "Inactive"

  const now = new Date()

  // Trial detection (ONLY ADDITION)
  if (profile.trial_end) {
    const trialEnd = new Date(profile.trial_end)
    if (trialEnd > now) {
      return "Trialing"
    }
  }

  // Active
  if (profile.subscription_status === "active") {
    return "Active"
  }

  // Everything else
  return "Inactive"
}
