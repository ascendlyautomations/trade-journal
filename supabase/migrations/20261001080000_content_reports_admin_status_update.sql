-- Admins can persist content-report review status.
-- RLS already limits UPDATE to admin_users and requires reviewed_by = auth.uid().
-- Authenticated previously had only SELECT and INSERT, so the native and web
-- status save failed closed for admins as well.

grant update (status, reviewed_at, reviewed_by)
  on table public.content_reports
  to authenticated;
