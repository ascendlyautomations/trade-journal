-- Screenshot / CSV import fingerprints for idempotent re-import detection.

alter table public.trades
  add column if not exists import_source text,
  add column if not exists import_fingerprint text;

comment on column public.trades.import_source is
  'Origin of the trade row: manual, csv, or screenshot. Null for legacy rows.';

comment on column public.trades.import_fingerprint is
  'Versioned deterministic import fingerprint (e.g. v1:<sha256>). Null for legacy/manual rows.';

create index if not exists trades_user_import_fingerprint_idx
  on public.trades (user_id, import_fingerprint)
  where import_fingerprint is not null;
