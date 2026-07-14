-- Manage complimentary Creator Access codes (no app deploy required).
-- Codes are stored uppercase; /creator?code=... normalizes input the same way.

-- Add a single-use code:
-- insert into public.creator_access_codes (code, label, notes)
-- values ('CREATOR-ALEX-01', 'Alex Rivera', 'Launch creator eval');

-- Add a multi-use code (e.g. 5 creators share one link):
-- insert into public.creator_access_codes (code, label, max_redemptions, notes)
-- values ('CREATOR-BATCH-Q3', 'Q3 batch', 5, 'Shared link');

-- Optional expiry:
-- update public.creator_access_codes
-- set expires_at = now() + interval '30 days'
-- where code = 'CREATOR-ALEX-01';

-- Disable a code (blocks future redemptions; existing grants keep Pro):
-- update public.creator_access_codes
-- set is_active = false
-- where code = 'CREATOR-ALEX-01';

-- Revoke a user's complimentary Pro (only if they have no paid/trial Stripe status):
-- update public.profiles
-- set
--   creator_access = false,
--   creator_code = null,
--   creator_granted_at = null,
--   is_pro = false
-- where id = '<user-uuid>'
--   and creator_access = true
--   and lower(trim(coalesce(subscription_status, ''))) not in ('active', 'trialing')
--   and (trial_end is null or trial_end <= now());
