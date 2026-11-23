-- TraxsPro interactive preview product analytics (iOS Phase 2).
-- Forward-only: extends allow-list and sanitized props for preview funnel events.

create or replace function public.product_analytics_allowed_event_names()
returns text[]
language sql
immutable
as $$
  select array[
    'session_started',
    'app_opened',
    'screen_viewed',
    'profile_viewed',
    'feature_used',
    'milestone_onboarding_completed',
    'milestone_first_trade',
    'traxspro_preview_started',
    'traxspro_preview_exited',
    'traxspro_preview_upgrade_tapped'
  ]::text[];
$$;

create or replace function public.product_analytics_sanitize_props(p_props jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_allowed text[] := array[
    'screen_id',
    'profile_id',
    'feature',
    'signup_flow_source',
    'entry_point',
    'preview_feature'
  ];
  v_key text;
  v_out jsonb := '{}'::jsonb;
  v_val text;
begin
  if p_props is null or p_props = 'null'::jsonb then
    return '{}'::jsonb;
  end if;
  if jsonb_typeof(p_props) <> 'object' then
    return '{}'::jsonb;
  end if;
  foreach v_key in array v_allowed loop
    if p_props ? v_key then
      v_val := left(trim(both '"' from (p_props ->> v_key)), 128);
      if v_val is not null and v_val <> '' then
        v_out := v_out || jsonb_build_object(v_key, v_val);
      end if;
    end if;
  end loop;
  return v_out;
end;
$$;