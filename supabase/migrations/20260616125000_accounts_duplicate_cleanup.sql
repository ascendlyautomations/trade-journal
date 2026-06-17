-- Remove duplicate accounts (same user_id + lower(trim(name))), keeping the oldest row.
-- Reassign trades and locked_account_id to the keeper before delete.

begin;

create temporary table accounts_duplicate_map on commit drop as
with ranked as (
  select
    id,
    user_id,
    lower(trim(name)) as norm_name,
    row_number() over (
      partition by user_id, lower(trim(name))
      order by created_at asc, id asc
    ) as rn
  from public.accounts
),
keepers as (
  select id as keep_id, user_id, norm_name
  from ranked
  where rn = 1
)
select
  r.id as delete_id,
  k.keep_id
from ranked r
inner join keepers k
  on k.user_id = r.user_id
 and k.norm_name = r.norm_name
where r.rn > 1;

update public.trades t
set account_id = m.keep_id
from accounts_duplicate_map m
where t.account_id = m.delete_id;

update public.profiles p
set locked_account_id = m.keep_id::text
from accounts_duplicate_map m
where p.locked_account_id = m.delete_id::text;

delete from public.accounts a
using accounts_duplicate_map m
where a.id = m.delete_id;

commit;
