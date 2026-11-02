/**
 * Profile content visibility — mirrors profile_posts / trades RLS and
 * `rpc_v1_profile_bootstrap` viewer.can_view_trades (owner, public, or follower).
 */
export function canViewPrivateProfileContent(
  profile: { id: string; is_private?: boolean | null } | null | undefined,
  viewerId: string | null | undefined,
  isFollowing: boolean
): boolean {
  if (!profile?.id) return false
  if (viewerId && String(viewerId) === String(profile.id)) return true
  if (profile.is_private !== true) return true
  return isFollowing
}
