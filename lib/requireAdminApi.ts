import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import type { User } from "@supabase/supabase-js"

type AdminApiSuccess = {
  adminUser: User
  error?: undefined
}

type AdminApiFailure = {
  adminUser?: undefined
  error: Response
}

export type RequireAdminApiResult = AdminApiSuccess | AdminApiFailure

/** Verifies the request is from a user listed in `admin_users`. */
export async function requireAdminApiUser(
  req: Request
): Promise<RequireAdminApiResult> {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return { error: Response.json({ error: "Unauthorized" }, { status: 401 }) }
  }

  const { data: adminRow } = await supabaseServiceRole
    .from("admin_users")
    .select("user_id")
    .eq("user_id", user.id)
    .maybeSingle()

  if (!adminRow?.user_id) {
    return { error: Response.json({ error: "Forbidden" }, { status: 403 }) }
  }

  return { adminUser: user }
}
