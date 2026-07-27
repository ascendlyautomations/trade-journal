import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { normalizeProfileUsername } from "@/lib/profileUsername"

/** Extract @usernames from room message text (case-insensitive, unique). */
export function extractMentionUsernames(content: string | null | undefined): string[] {
  const text = String(content ?? "")
  if (!text.trim()) return []

  const matches = text.matchAll(/@([a-z0-9_]+)/gi)
  const seen = new Set<string>()
  const usernames: string[] = []
  for (const match of matches) {
    const normalized = normalizeProfileUsername(match[1] ?? "")
    if (!normalized || seen.has(normalized)) continue
    seen.add(normalized)
    usernames.push(normalized)
  }
  return usernames
}

/** Resolve mention usernames to profile ids. Unknown usernames are dropped. */
export async function resolveMentionUserIds(
  usernames: string[]
): Promise<Map<string, string>> {
  const unique = [...new Set(usernames.map((u) => normalizeProfileUsername(u)).filter(Boolean))]
  if (unique.length === 0) return new Map()

  const { data, error } = await supabaseServiceRole
    .from("profiles")
    .select("id, username")
    .in("username", unique)

  if (error) {
    console.error("[messaging] mention username resolve failed", error)
    return new Map()
  }

  const byUsername = new Map<string, string>()
  for (const row of data ?? []) {
    const username = normalizeProfileUsername(String(row.username ?? ""))
    const id = String(row.id ?? "").trim()
    if (!username || !id) continue
    byUsername.set(username, id)
  }
  return byUsername
}

export async function resolveMentionedUserIdsFromContent(
  content: string | null | undefined,
  opts?: { excludeUserId?: string | null }
): Promise<string[]> {
  const usernames = extractMentionUsernames(content)
  if (usernames.length === 0) return []

  const byUsername = await resolveMentionUserIds(usernames)
  const exclude = opts?.excludeUserId?.trim() ?? ""
  const ids: string[] = []
  const seen = new Set<string>()
  for (const username of usernames) {
    const id = byUsername.get(username)
    if (!id || id === exclude || seen.has(id)) continue
    seen.add(id)
    ids.push(id)
  }
  return ids
}
