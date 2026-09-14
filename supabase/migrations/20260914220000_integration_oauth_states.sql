-- Server-side OAuth state for broker integrations (Tradovate first).
-- Only the service role may read/write; browsers never receive user_id in the state param.

create table if not exists public.integration_oauth_states (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  state_token text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  redirect_after text,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint integration_oauth_states_state_token_unique unique (state_token),
  constraint integration_oauth_states_provider_check check (char_length(provider) > 0)
);

create index if not exists integration_oauth_states_expires_at_idx
  on public.integration_oauth_states (expires_at);

create index if not exists integration_oauth_states_user_provider_idx
  on public.integration_oauth_states (user_id, provider, created_at desc);

comment on table public.integration_oauth_states is
  'One-time OAuth CSRF state tokens binding an authorization attempt to a TradeTraxs user.';

alter table public.integration_oauth_states enable row level security;

-- No policies: authenticated/anon clients cannot access; BFF uses service role only.
