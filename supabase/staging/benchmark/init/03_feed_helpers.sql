create or replace function public._v1_feed_before_cursor(
  p_row_ts timestamptz,
  p_row_kind text,
  p_row_id uuid,
  p_cursor_ts timestamptz,
  p_cursor_kind text,
  p_cursor_id uuid,
  p_cursor_kind_rank integer,
  p_legacy_only boolean
)
returns boolean
language sql
stable
as $$
  select
    p_cursor_ts is null
    or (
      p_legacy_only
      and p_row_ts < p_cursor_ts
    )
    or (
      not coalesce(p_legacy_only, false)
      and (
        p_row_ts < p_cursor_ts
        or (
          p_row_ts = p_cursor_ts
          and (
            p_cursor_kind is null
            or p_row_id < p_cursor_id
          )
        )
      )
    );
$$;

grant execute on function public._v1_feed_before_cursor(
  timestamptz, text, uuid, timestamptz, text, uuid, integer, boolean
) to authenticated;
