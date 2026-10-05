-- Feed trade payload: expose copy linkage fields needed for batch dedupe + mode summaries.

create or replace function public._v1_feed_post_trade_payload(
  p_trade_id uuid,
  p_reel public.reels,
  p_guest boolean
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $fn$
  select case
    when t.id is null then null
    when p_guest and coalesce(t.is_public, false) = false then null
    when p_guest then jsonb_build_object(
      'created_at', t.created_at,
      'public_description', t.public_description,
      'user_id', t.user_id,
      'ticker', t.ticker,
      'direction', t.direction,
      'account_type', t.account_type,
      'mode', t.mode,
      'trade_mode', t.trade_mode,
      'points', t.points,
      'entry_time', t.entry_time,
      'exit_time', t.exit_time,
      'entry_price', t.entry_price,
      'exit_price', t.exit_price,
      'trade_date', t.trade_date,
      'duration_seconds', t.duration_seconds,
      'duration_text', t.duration_text,
      'image_url', t.image_url,
      'image_crop', t.image_crop,
      'is_public', true,
      'reels', case
        when p_reel.id is null or coalesce(p_reel.visibility, 'public') <> 'public' then null
        else jsonb_build_object(
          'id', p_reel.id,
          'user_id', p_reel.user_id,
          'video_url', p_reel.video_url,
          'thumbnail_url', p_reel.thumbnail_url,
          'duration_seconds', p_reel.duration_seconds,
          'trade_id', p_reel.trade_id,
          'visibility', p_reel.visibility
        )
      end
    )
    else jsonb_build_object(
      'created_at', t.created_at,
      'public_description', t.public_description,
      'user_id', t.user_id,
      'account_id', t.account_id,
      'source_account_id', t.source_account_id,
      'ticker', t.ticker,
      'direction', t.direction,
      'account_type', t.account_type,
      'mode', t.mode,
      'trade_mode', t.trade_mode,
      'copied_account_ids', t.copied_account_ids,
      'copy_trading_group_id', t.copy_trading_group_id,
      'points', t.points,
      'entry_time', t.entry_time,
      'exit_time', t.exit_time,
      'entry_price', t.entry_price,
      'exit_price', t.exit_price,
      'trade_date', t.trade_date,
      'duration_seconds', t.duration_seconds,
      'duration_text', t.duration_text,
      'image_url', t.image_url,
      'image_crop', t.image_crop,
      'reels', case when p_reel.id is null then null else jsonb_build_object(
        'id', p_reel.id,
        'user_id', p_reel.user_id,
        'video_url', p_reel.video_url,
        'thumbnail_url', p_reel.thumbnail_url,
        'duration_seconds', p_reel.duration_seconds,
        'trade_id', p_reel.trade_id,
        'visibility', p_reel.visibility
      ) end
    )
  end
  from (
    select
      id,
      created_at,
      public_description,
      user_id,
      account_id,
      source_account_id,
      ticker,
      direction,
      account_type,
      mode,
      trade_mode,
      copied_account_ids,
      copy_trading_group_id,
      points,
      entry_time,
      exit_time,
      entry_price,
      exit_price,
      trade_date,
      duration_seconds,
      duration_text,
      image_url,
      image_crop,
      is_public
    from public.trades
    where id = p_trade_id
  ) t;
$fn$;
