-- Allow admins to review / update affiliate payout requests.

drop policy if exists "affiliate_payout_requests_update_admin" on public.affiliate_payout_requests;

create policy "affiliate_payout_requests_update_admin"
  on public.affiliate_payout_requests for update to authenticated
  using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()))
  with check (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));
