import {
  isSupabaseStoragePublicUrl,
  normalizeImageSrc,
} from "./optimizedStorageImage.ts"
import { supabaseStorageDeliveryUrl } from "./supabaseStorageTransformGuard.ts"

/**
 * Resolve profile avatar URLs (full public URL, storage path under user id, or
 * legacy render URL). Shared by SafeProfileAvatar and broadcast chat.
 */
export function normalizeAvatarSrc(src: string | null | undefined): string | null {
  const raw = normalizeImageSrc(src)
  if (!raw) return null

  if (/^https?:\/\//i.test(raw) || raw.startsWith("//")) {
    return isSupabaseStoragePublicUrl(raw)
      ? supabaseStorageDeliveryUrl(raw)
      : raw
  }

  if (raw.startsWith("/") && !raw.startsWith("//")) {
    return raw
  }

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, "")
  if (!base) return raw

  const path = raw.replace(/^\/+/, "")
  if (/^[0-9a-f-]{36}\//i.test(path)) {
    return `${base}/storage/v1/object/public/avatars/${path}`
  }

  return raw
}
