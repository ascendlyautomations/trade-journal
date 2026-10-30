const PSYCHOLOGY_SCOPE_TRADE_CAP = 500

function scopedTradeFingerprint(
  trades: ReadonlyArray<{ id?: unknown; updated_at?: unknown; created_at?: unknown }>
): string {
  const ids = trades
    .map((row) => String(row.id ?? ""))
    .filter(Boolean)
    .slice(0, PSYCHOLOGY_SCOPE_TRADE_CAP)
  return `${ids.length}:${ids[0] ?? ""}:${ids[ids.length - 1] ?? ""}`
}

export type PsychologyAnalyticsScope = {
  userId: string
  fingerprint: string
  label: string
  trades: ReadonlyArray<Record<string, unknown>>
}

export function buildPsychologyScopeFingerprint(
  userId: string,
  scopeLabel: string,
  trades: ReadonlyArray<{ id?: unknown; updated_at?: unknown; created_at?: unknown }>
): string {
  return `${userId}|${scopeLabel}|${scopedTradeFingerprint(trades)}`
}

export function createPsychologyAnalyticsScope(
  userId: string,
  scopeLabel: string,
  trades: ReadonlyArray<Record<string, unknown>>
): PsychologyAnalyticsScope {
  return {
    userId,
    label: scopeLabel,
    trades,
    fingerprint: buildPsychologyScopeFingerprint(userId, scopeLabel, trades),
  }
}
