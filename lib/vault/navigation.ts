import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import type { VaultItem } from "./types"

export async function resolveVaultItemHref(
  client: SupabaseClient<Database>,
  item: VaultItem
): Promise<string> {
  const { contentType, contentID } = item.ref
  switch (contentType) {
    case "trade":
      return `/trade/${contentID}`
    case "profile_post":
    case "feed_post":
      return `/feed?post=${encodeURIComponent(contentID)}`
    case "reel":
      return `/feed?reel=${encodeURIComponent(contentID)}`
    case "achievement": {
      const { data } = await client
        .from("achievements")
        .select("user_id")
        .eq("id", contentID)
        .maybeSingle()
      if (data?.user_id) {
        return `/profile/${data.user_id}?achievement=${encodeURIComponent(contentID)}`
      }
      return "/achievements"
    }
    default:
      return "/vault"
  }
}
