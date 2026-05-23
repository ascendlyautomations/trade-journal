export function postImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

export function postPublicDescription(post: any): string | null {
  const t = post?.trades
  if (!t) return null
  const row = Array.isArray(t) ? t[0] : t
  const raw = row?.public_description
  if (raw == null) return null
  const s = String(raw).trim()
  return s !== "" ? s : null
}

export function postTradeJoin(post: any) {
  const t = post?.trades
  if (!t) return null
  return Array.isArray(t) ? t[0] : t
}

export function getModeStyles(mode: string | null | undefined): string {
  if (!mode) return ""
  const m = mode.toLowerCase()
  if (m === "funded") return "bg-green-500/20 text-green-300"
  if (m === "eval") return "bg-yellow-500/20 text-yellow-300"
  if (m === "live") return "bg-blue-500/20 text-blue-300"
  return "bg-white/10 text-gray-300"
}
