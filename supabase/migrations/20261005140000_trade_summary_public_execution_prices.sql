-- Public TradeSummary — include execution prices for shared/social surfaces (no journal notes).

create or replace function public.trade_summary_json(
  p_trade public.trades,
  p_viewer_id uuid default null
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_strip_nulls(
    jsonb_build_object(
      'summary_schema', 'trade_summary_v1',
      'id', p_trade.id,
      'user_id', p_trade.user_id,
      'ticker', p_trade.ticker,
      'direction', p_trade.direction,
      'pnl', p_trade.pnl,
      'rr', p_trade.rr,
      'points', p_trade.points,
      'contracts', p_trade.contracts,
      'entry_time', public.analytics_wire_trade_timestamp_utc(p_trade.entry_time),
      'exit_time', public.analytics_wire_trade_timestamp_utc(p_trade.exit_time),
      'entry_price', p_trade.entry_price,
      'exit_price', p_trade.exit_price,
      'created_at', to_char(
        p_trade.created_at at time zone 'utc',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'is_public', coalesce(p_trade.is_public, false),
      'public_description', p_trade.public_description,
      'note_preview', public.trade_summary_note_preview(p_trade, p_viewer_id),
      'image_url', p_trade.image_url,
      'image_crop', p_trade.image_crop,
      'image_display_mode', p_trade.image_display_mode,
      'mode', p_trade.mode,
      'account_type', p_trade.account_type,
      'trade_mode', p_trade.trade_mode,
      'duration_seconds', p_trade.duration_seconds,
      'duration_text', p_trade.duration_text
    )
  );
$$;

comment on function public.trade_summary_json(public.trades, uuid) is
  'Phase 8B canonical TradeSummary wire object for list/card surfaces. Includes public execution prices.';
