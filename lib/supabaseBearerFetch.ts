import { supabase } from "@/lib/supabaseClient"

/**
 * Headers so API routes can authenticate the browser session. The default Supabase JS client persists
 * sessions in localStorage (not cookies), while `getRouteUser` resolves the user from cookies OR
 * `Authorization: Bearer`.
 */
export async function supabaseBearerHeaders(): Promise<HeadersInit> {
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token
  return token ? { Authorization: `Bearer ${token}` } : {}
}
