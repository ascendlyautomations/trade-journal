import type { SupabaseClient } from "@supabase/supabase-js"
import { supabase } from "@/lib/supabaseClient"

export type DmPrivacy = "everyone" | "following" | "followers" | "mutual"

export const DM_PRIVACY_OPTIONS: ReadonlyArray<{
  value: DmPrivacy
  title: string
  subtitle: string
}> = [
  {
    value: "everyone",
    title: "Everyone",
    subtitle: "Any trader can start a direct message with you.",
  },
  {
    value: "following",
    title: "People I follow",
    subtitle: "Only accounts you follow can message you.",
  },
  {
    value: "followers",
    title: "Followers",
    subtitle: "Only accounts that follow you can message you.",
  },
  {
    value: "mutual",
    title: "Mutual follows",
    subtitle: "Only mutual follows can message you.",
  },
]

export function parseDmPrivacy(raw: unknown): DmPrivacy {
  const trimmed = String(raw ?? "")
    .trim()
    .toLowerCase()
  if (
    trimmed === "everyone" ||
    trimmed === "following" ||
    trimmed === "followers" ||
    trimmed === "mutual"
  ) {
    return trimmed
  }
  return "everyone"
}

export function dmPrivacyTitle(value: DmPrivacy): string {
  return DM_PRIVACY_OPTIONS.find((o) => o.value === value)?.title ?? "Everyone"
}

export async function fetchOwnerDmPrivacy(
  userId: string,
  client: SupabaseClient = supabase
): Promise<{ ok: true; value: DmPrivacy } | { ok: false; message: string }> {
  const id = String(userId ?? "").trim()
  if (!id) {
    return { ok: false, message: "Sign in to manage messaging privacy." }
  }
  const { data, error } = await client
    .from("profiles")
    .select("dm_privacy")
    .eq("id", id)
    .maybeSingle()
  if (error) {
    return { ok: false, message: error.message }
  }
  return { ok: true, value: parseDmPrivacy(data?.dm_privacy) }
}

export async function persistOwnerDmPrivacy(
  userId: string,
  value: DmPrivacy,
  client: SupabaseClient = supabase
): Promise<{ ok: true; value: DmPrivacy } | { ok: false; message: string }> {
  const id = String(userId ?? "").trim()
  if (!id) {
    return { ok: false, message: "Sign in to manage messaging privacy." }
  }
  const { data, error } = await client
    .from("profiles")
    .update({ dm_privacy: value })
    .eq("id", id)
    .select("dm_privacy")
    .maybeSingle()
  if (error) {
    return { ok: false, message: error.message }
  }
  return { ok: true, value: parseDmPrivacy(data?.dm_privacy) }
}
