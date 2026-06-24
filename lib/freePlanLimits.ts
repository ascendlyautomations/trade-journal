import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "@/lib/subscription"

export async function isUserPro(
  client: SupabaseClient,
  userId: string
): Promise<boolean> {
  const { data } = await client
    .from("profiles")
    .select("is_pro, subscription_status")
    .eq("id", userId)
    .maybeSingle()

  return isProActive(data)
}
