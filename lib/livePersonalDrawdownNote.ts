export type LiveWithdrawalDrawdownBehavior =
  | "reset_to_account"
  | "keep_trailing"

export const LIVE_WITHDRAWAL_DD_NOTE_RESET = "[[tt:dd=reset]]"
export const LIVE_WITHDRAWAL_DD_NOTE_KEEP = "[[tt:dd=keep]]"

export function encodeWithdrawalDrawdownNote(
  behavior: LiveWithdrawalDrawdownBehavior,
  userNote: string
): string {
  const prefix =
    behavior === "reset_to_account"
      ? LIVE_WITHDRAWAL_DD_NOTE_RESET
      : LIVE_WITHDRAWAL_DD_NOTE_KEEP
  const trimmed = String(userNote ?? "").trim()
  return trimmed ? `${prefix}${trimmed}` : prefix
}

export function parseWithdrawalDrawdownBehaviorFromNote(
  note: string | null | undefined
): LiveWithdrawalDrawdownBehavior | null {
  const n = String(note ?? "")
  if (n.startsWith(LIVE_WITHDRAWAL_DD_NOTE_RESET)) return "reset_to_account"
  if (n.startsWith(LIVE_WITHDRAWAL_DD_NOTE_KEEP)) return "keep_trailing"
  return null
}

export function stripWithdrawalDrawdownNotePrefix(
  note: string | null | undefined
): string {
  const n = String(note ?? "")
  if (n.startsWith(LIVE_WITHDRAWAL_DD_NOTE_RESET)) {
    return n.slice(LIVE_WITHDRAWAL_DD_NOTE_RESET.length).trim()
  }
  if (n.startsWith(LIVE_WITHDRAWAL_DD_NOTE_KEEP)) {
    return n.slice(LIVE_WITHDRAWAL_DD_NOTE_KEEP.length).trim()
  }
  return n.trim()
}
