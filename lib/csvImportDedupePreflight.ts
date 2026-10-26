/**
 * Read-only SQL checks before applying `20261026140000_phase2_trading_data_integrity.sql`.
 * Run in staging/production SQL editor — do not auto-delete rows from application code.
 */

export const CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES = {
  withAccount: `
SELECT user_id, account_id, import_fingerprint, count(*) AS row_count
FROM public.trades
WHERE import_source = 'csv'
  AND import_fingerprint IS NOT NULL
  AND account_id IS NOT NULL
GROUP BY 1, 2, 3
HAVING count(*) > 1
ORDER BY row_count DESC
LIMIT 100;
`.trim(),

  withoutAccount: `
SELECT user_id, import_fingerprint, count(*) AS row_count
FROM public.trades
WHERE import_source = 'csv'
  AND import_fingerprint IS NOT NULL
  AND account_id IS NULL
GROUP BY 1, 2
HAVING count(*) > 1
ORDER BY row_count DESC
LIMIT 100;
`.trim(),

  /** Rows that would get fingerprints on the next CSV import path but lack them today. */
  legacyCsvWithoutFingerprint: `
SELECT count(*) AS legacy_csv_rows_missing_fingerprint
FROM public.trades
WHERE import_source IS DISTINCT FROM 'csv'
  AND import_fingerprint IS NULL
  AND coalesce(account_type, '') = 'imported';
`.trim(),
} as const

/** Migration is safe to apply when both duplicate probes return zero rows. */
export function csvImportDedupeMigrationBlocked(
  duplicateWithAccountCount: number,
  duplicateWithoutAccountCount: number
): boolean {
  return duplicateWithAccountCount > 0 || duplicateWithoutAccountCount > 0
}
