import { isDemoUserId } from "@/lib/demo/constants"
import { isGuestExploreViewer } from "@/lib/guestExplore"
import { supabase } from "@/lib/supabaseClient"

let refreshInFlight: Promise<string | null> | null = null

/** True when the user may call member APIs (not guest explore / demo viewer). */
export function isAuthenticatedMemberUser(
  user: { id: string } | null | undefined
): boolean {
  if (!user?.id) return false
  if (isGuestExploreViewer(user)) return false
  if (isDemoUserId(user.id)) return false
  return true
}

/**
 * Resolves a bearer token only when Supabase considers the session valid
 * (`getUser`), refreshing once when the cached access token is stale.
 * Guest explore JWTs return null — they must not hit member BFF routes.
 */
export async function getSupabaseApiAccessToken(options?: {
  allowRefresh?: boolean
}): Promise<string | null> {
  const allowRefresh = options?.allowRefresh !== false

  const { data: sessionData } = await supabase.auth.getSession()
  const session = sessionData.session
  if (!session?.access_token) return null
  if (!isAuthenticatedMemberUser(session.user)) return null

  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (!userError && userData.user && isAuthenticatedMemberUser(userData.user)) {
    return session.access_token
  }

  if (!allowRefresh) return null

  if (!refreshInFlight) {
    refreshInFlight = (async () => {
      try {
        const { data, error } = await supabase.auth.refreshSession()
        const refreshed = data.session
        if (error || !refreshed?.access_token) return null
        if (!isAuthenticatedMemberUser(refreshed.user)) return null
        const { data: verify, error: verifyErr } = await supabase.auth.getUser()
        if (verifyErr || !verify.user || !isAuthenticatedMemberUser(verify.user)) {
          return null
        }
        return refreshed.access_token
      } finally {
        refreshInFlight = null
      }
    })()
  }

  return refreshInFlight
}

/**
 * Headers so API routes can authenticate the browser session. The default Supabase JS client persists
 * sessions in localStorage (not cookies), while `getRouteUser` resolves the user from cookies OR
 * `Authorization: Bearer`.
 */
export async function supabaseBearerHeaders(): Promise<HeadersInit> {
  const token = await getSupabaseApiAccessToken()
  return token ? { Authorization: `Bearer ${token}` } : {}
}
