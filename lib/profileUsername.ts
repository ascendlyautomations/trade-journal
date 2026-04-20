/** Postgres duplicate key — narrow to profiles.username unique constraint when possible */
export function isProfilesUsernameConflict(err: {
  code?: string
  message?: string
  details?: string | null
}): boolean {
  if (err.code !== "23505") return false
  const s = `${err.message ?? ""} ${err.details ?? ""}`.toLowerCase()
  return s.includes("username")
}
