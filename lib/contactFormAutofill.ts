import { fetchSettingsProfileRow } from "@/lib/settingsProfileSync"
import { readSettingsProfileCache } from "@/lib/settingsProfileCache"
import { supabase } from "@/lib/supabaseClient"

export type ContactFormAutofill = {
  name: string
  email: string
}

/** Resolve contact form defaults from cached profile when possible; fetches only on cache miss. */
export async function resolveContactFormAutofill(
  userId: string,
  userEmail: string | null | undefined
): Promise<ContactFormAutofill> {
  const email = userEmail?.trim() ?? ""
  const cached = readSettingsProfileCache(userId)
  const cachedName =
    typeof cached?.name === "string" ? cached.name.trim() : ""

  if (cachedName) {
    return { name: cachedName, email }
  }

  const row = await fetchSettingsProfileRow(supabase, userId)
  const name = typeof row?.name === "string" ? row.name.trim() : ""
  return { name, email }
}
