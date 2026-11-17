-- Later body-only replacements switched this RPC to SECURITY INVOKER, which surfaces
-- 403/permission failures under trade/check-in RLS despite auth.uid() scoping in SQL.
-- Keep INVOKER semantics out of band; DEFINER + auth.uid() matches viewer-sync bootstrap RPCs.

alter function public.rpc_v1_psychology_check_in_window(uuid) security definer;