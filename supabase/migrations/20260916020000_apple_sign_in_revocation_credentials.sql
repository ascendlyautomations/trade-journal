-- Sign in with Apple refresh tokens for server-side revocation on account deletion.
-- Service-role only (no RLS policies); ciphertext encrypted in the BFF.

create table if not exists public.apple_sign_in_credentials (
  user_id uuid primary key references auth.users (id) on delete cascade,
  client_id text not null,
  refresh_token_ciphertext text not null,
  apple_sub text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint apple_sign_in_credentials_client_id_check check (char_length(client_id) > 0),
  constraint apple_sign_in_credentials_ciphertext_check check (
    char_length(refresh_token_ciphertext) > 0
  )
);

comment on table public.apple_sign_in_credentials is
  'Encrypted Apple Sign in refresh tokens for account-deletion revocation. BFF service role only.';

alter table public.apple_sign_in_credentials enable row level security;

create table if not exists public.apple_sign_in_revoke_queue (
  id uuid primary key default gen_random_uuid(),
  refresh_token_ciphertext text not null,
  client_id text not null,
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  next_attempt_at timestamptz not null default now(),
  constraint apple_sign_in_revoke_queue_client_id_check check (char_length(client_id) > 0),
  constraint apple_sign_in_revoke_queue_ciphertext_check check (
    char_length(refresh_token_ciphertext) > 0
  )
);

create index if not exists apple_sign_in_revoke_queue_next_attempt_idx
  on public.apple_sign_in_revoke_queue (next_attempt_at asc);

comment on table public.apple_sign_in_revoke_queue is
  'Pending Apple token revocations when revoke fails during account deletion. BFF service role only.';

alter table public.apple_sign_in_revoke_queue enable row level security;

revoke all on table public.apple_sign_in_credentials from public, anon, authenticated;
revoke all on table public.apple_sign_in_revoke_queue from public, anon, authenticated;
