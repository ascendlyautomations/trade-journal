/** Shared Unicode emoji validation — native `MessageReactionValidation` parity. */

const MAX_CODE_POINTS = 16
const MAX_BYTES = 64

export function normalizeMessageReaction(raw: string): string | null {
  const trimmed = raw.normalize("NFC").trim()
  if (!trimmed) return null
  if (trimmed.length > MAX_CODE_POINTS) return null
  if (new TextEncoder().encode(trimmed).length > MAX_BYTES) return null
  if (/[\u0000-\u001F\u007F]/.test(trimmed)) return null
  if (!hasEmojiPresentation(trimmed)) return null
  return trimmed
}

export function isValidMessageReaction(raw: string): boolean {
  return normalizeMessageReaction(raw) != null
}

/** Quick row in menus + double-tap default. */
export const MESSAGE_REACTION_QUICK_PICKS = [
  "❤️",
  "👍",
  "🔥",
  "😂",
  "‼️",
] as const

/** @deprecated Use MESSAGE_REACTION_QUICK_PICKS — kept for import compatibility. */
export const MESSAGE_REACTION_DOUBLE_TAP_EMOJI =
  MESSAGE_REACTION_QUICK_PICKS[0]

function hasEmojiPresentation(value: string): boolean {
  for (const char of value) {
    const cp = char.codePointAt(0) ?? 0
    if (isEmojiCodePoint(cp) || char === "\u200D" || char === "\uFE0F") {
      return true
    }
  }
  return false
}

function isEmojiCodePoint(cp: number): boolean {
  if (cp >= 0x1f000 && cp <= 0x1faff) return true
  if (cp >= 0x2600 && cp <= 0x27bf) return true
  if (cp >= 0x2300 && cp <= 0x23ff) return true
  if (cp === 0x2b50 || cp === 0x2764) return true
  if (cp >= 0x1f3fb && cp <= 0x1f3ff) return true
  return false
}