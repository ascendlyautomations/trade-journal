-- Synthetic feed cand benchmark data. Set bench.scale via set_config before running.

create or replace function public.bench_uuid(n bigint)
returns uuid
language sql
immutable
set search_path = public
as $$
  select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;

truncate public.posts, public.profile_posts, public.achievement_posts, public.reels,
  public.achievements, public.trades, public.followers, public.user_blocks, public.profiles cascade;

insert into public.profiles (id, username, is_private)
select public.bench_uuid(i), 'author_' || i, (i % 17 = 0)
from generate_series(1, 1200) g(i);

-- Viewers: 15 / 40 / 100 / 500 follows + private-follow viewer + block fixture viewer
insert into public.profiles (id, username, is_private) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-000000000015'::uuid, 'viewer_15', false),
  ('aaaaaaaa-aaaa-4aaa-8aaa-000000000040'::uuid, 'viewer_40', false),
  ('aaaaaaaa-aaaa-4aaa-8aaa-000000000100'::uuid, 'viewer_100', false),
  ('aaaaaaaa-aaaa-4aaa-8aaa-000000000500'::uuid, 'viewer_500', false),
  ('bbbbbbbb-bbbb-4bbb-8bbb-000000000001'::uuid, 'viewer_private', false),
  ('bbbbbbbb-bbbb-4bbb-8bbb-000000000002'::uuid, 'viewer_block', false);

insert into public.followers (follower_id, following_id)
select 'aaaaaaaa-aaaa-4aaa-8aaa-000000000015'::uuid, public.bench_uuid(i)
from generate_series(1, 15) g(i);

insert into public.followers (follower_id, following_id)
select 'aaaaaaaa-aaaa-4aaa-8aaa-000000000040'::uuid, public.bench_uuid(i)
from generate_series(1, 40) g(i);

insert into public.followers (follower_id, following_id)
select 'aaaaaaaa-aaaa-4aaa-8aaa-000000000100'::uuid, public.bench_uuid(i)
from generate_series(1, 100) g(i);

insert into public.followers (follower_id, following_id)
select 'aaaaaaaa-aaaa-4aaa-8aaa-000000000500'::uuid, public.bench_uuid(i)
from generate_series(1, 500) g(i);

-- viewer_private follows a private author only
insert into public.profiles (id, username, is_private)
values (public.bench_uuid(9999), 'private_only', true)
on conflict (id) do update set is_private = true;

insert into public.followers (follower_id, following_id)
values ('bbbbbbbb-bbbb-4bbb-8bbb-000000000001'::uuid, public.bench_uuid(9999));

-- block fixture: viewer_block follows author_1 but blocks them
insert into public.followers (follower_id, following_id)
values ('bbbbbbbb-bbbb-4bbb-8bbb-000000000002'::uuid, public.bench_uuid(1));

insert into public.user_blocks (blocker_id, blocked_id)
values ('bbbbbbbb-bbbb-4bbb-8bbb-000000000002'::uuid, public.bench_uuid(1));

-- posting volume
do $$
declare
  v_scale text := coalesce(nullif(current_setting('bench.scale', true), ''), 'sparse');
  v_post_total int := case when v_scale = 'large' then 350000 else 12000 end;
  v_noise_authors int := case when v_scale = 'large' then 700 else 200 end;
  v_author int;
  v_posts int;
  v_i int;
  v_ts timestamptz;
begin
  perform set_config('bench.scale', v_scale, true);

  for v_author in 1..1200 loop
    v_posts := case
      when v_author % 23 = 0 then 1
      when v_author % 7 = 0 then 5
      when v_author % 3 = 0 then 25
      else 12
    end;
    if v_author > v_noise_authors then
      v_posts := greatest(1, v_posts / 4);
    end if;

    for v_i in 1..v_posts loop
      v_ts := timestamptz '2025-01-01' + ((v_author * 97 + v_i * 13) % 525600) * interval '1 minute';
      insert into public.posts (user_id, created_at)
      values (public.bench_uuid(v_author), v_ts);
    end loop;

    for v_i in 1..(v_posts / 2) loop
      v_ts := timestamptz '2025-02-01' + ((v_author * 41 + v_i * 17) % 525600) * interval '1 minute';
      insert into public.profile_posts (user_id, content, created_at)
      values (public.bench_uuid(v_author), 'pp', v_ts);
    end loop;

    insert into public.achievements (id, user_id, is_public)
    values (public.bench_uuid(100000 + v_author), public.bench_uuid(v_author), true);

    for v_i in 1..(v_posts / 3) loop
      v_ts := timestamptz '2025-03-01' + ((v_author * 29 + v_i * 11) % 525600) * interval '1 minute';
      insert into public.achievement_posts (user_id, achievement_id, created_at)
      values (
        public.bench_uuid(v_author),
        public.bench_uuid(100000 + v_author),
        v_ts
      );
    end loop;

    for v_i in 1..(v_posts / 4) loop
      v_ts := timestamptz '2025-04-01' + ((v_author * 31 + v_i * 19) % 525600) * interval '1 minute';
      insert into public.reels (user_id, created_at, trade_id, visibility)
      values (public.bench_uuid(v_author), v_ts, null, 'public');
    end loop;
  end loop;

  -- pad posts toward target (timeline noise from non-followed heavy authors)
  insert into public.posts (user_id, created_at)
  select public.bench_uuid(500 + (g % 500)), timestamptz '2026-01-01' - (g * interval '1 minute')
  from generate_series(1, greatest(0, v_post_total - (select count(*)::int from public.posts))) g;
end $$;

analyze public.posts;
analyze public.profile_posts;
analyze public.achievement_posts;
analyze public.reels;
analyze public.followers;
