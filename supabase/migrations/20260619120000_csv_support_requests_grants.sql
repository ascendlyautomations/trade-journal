-- csv_support_requests: explicit table privileges for authenticated role.
-- RLS policies from 20260528153000 remain unchanged (owner insert/select, admin read/update).

grant select, insert on table public.csv_support_requests to authenticated;
grant update on table public.csv_support_requests to authenticated;
