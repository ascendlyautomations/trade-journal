-- Per-user counts for admin detail (SECURITY DEFINER; admin-only gate inside).
create or replace function public.admin_user_activity_counts(p_target uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (select 1 from public.admin_users au where au.user_id = auth.uid()) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'trades', (select count(*)::bigint from public.trades t where t.user_id = p_target),
    'posts', (select count(*)::bigint from public.posts p where p.user_id = p_target),
    'achievements', (select count(*)::bigint from public.achievements a where a.user_id = p_target),
    'feedback', (select count(*)::bigint from public.feedback_submissions f where f.user_id = p_target),
    'supportTickets', (select count(*)::bigint from public.support_tickets st where st.user_id = p_target)
  );
end;
$$;

revoke all on function public.admin_user_activity_counts(uuid) from public;
grant execute on function public.admin_user_activity_counts(uuid) to authenticated;
