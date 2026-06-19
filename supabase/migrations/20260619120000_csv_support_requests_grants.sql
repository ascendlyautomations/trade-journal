-- csv_support_requests: table privileges for authenticated role (matches bug_reports / feature_requests).
-- RLS policies from 20260528153000 remain unchanged (owner insert/select, admin read/update).
-- Without INSERT grant, PostgREST inserts fail even when user_id = auth.uid().

revoke all on table public.csv_support_requests from anon;

grant select, insert on table public.csv_support_requests to authenticated;
grant update on table public.csv_support_requests to authenticated;
