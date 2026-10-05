-- Admin draft editing for the published Demo snapshot.
-- Entity rows are the draft. demo.publications stays the version history.
-- Visitors still read only public.rpc_v1_demo_snapshot().

alter table demo.profiles add column if not exists sort_order integer not null default 0;
alter table demo.accounts add column if not exists sort_order integer not null default 0;
alter table demo.trades add column if not exists sort_order integer not null default 0;
alter table demo.check_ins add column if not exists sort_order integer not null default 0;
alter table demo.payouts add column if not exists sort_order integer not null default 0;
alter table demo.posts add column if not exists sort_order integer not null default 0;
alter table demo.clips add column if not exists sort_order integer not null default 0;
alter table demo.stories add column if not exists sort_order integer not null default 0;
alter table demo.achievements add column if not exists sort_order integer not null default 0;
alter table demo.activity add column if not exists sort_order integer not null default 0;
alter table demo.conversations add column if not exists sort_order integer not null default 0;
alter table demo.messages add column if not exists sort_order integer not null default 0;
alter table demo.rooms add column if not exists sort_order integer not null default 0;
alter table demo.room_channels add column if not exists sort_order integer not null default 0;
alter table demo.room_memberships add column if not exists sort_order integer not null default 0;
alter table demo.room_messages add column if not exists sort_order integer not null default 0;
alter table demo.vault_folders add column if not exists sort_order integer not null default 0;
alter table demo.vault_items add column if not exists sort_order integer not null default 0;

alter table demo.publications add column if not exists published_by uuid;
alter table demo.publications add column if not exists publisher_email text;
alter table demo.publications add column if not exists restored_from integer;

-- Keep draft array order identical to the current published document.
update demo.profiles p
set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'peers') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where p.id = src.id;

update demo.accounts a
set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'accounts') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.trades a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'trades') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.check_ins a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'checkIns') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.payouts a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'payouts') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.posts a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'posts') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.clips a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'clips') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.stories a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'stories') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.achievements a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'achievements') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.activity a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'activity') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.conversations a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'conversations') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.messages a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'messages') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.room_channels a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'channels') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.room_memberships a set sort_order = src.ord
from (
  select item->>'roomID' as room_id, item->>'profileID' as profile_id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'memberships') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.room_id = src.room_id and a.profile_id = src.profile_id;

update demo.room_messages a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'roomMessages') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.vault_folders a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'vaultFolders') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

update demo.vault_items a set sort_order = src.ord
from (
  select item->>'id' as id, (ordinality - 1)::integer as ord
  from demo.publications pub
  cross join lateral jsonb_array_elements(pub.snapshot->'vaultItems') with ordinality as t(item, ordinality)
  where pub.is_current
) src
where a.id = src.id;

create or replace function demo.assemble_draft(p_version integer, p_published_at text)
returns jsonb
language sql
stable
security definer
set search_path = demo, pg_temp
as $fn$
  select jsonb_build_object(
    'schemaVersion', 1,
    'version', p_version,
    'publishedAt', p_published_at,
    'viewer', (select payload from profiles where role = 'viewer' order by sort_order, id limit 1),
    'peers', coalesce((select jsonb_agg(payload order by sort_order, id) from profiles where role = 'peer'), '[]'::jsonb),
    'host', (select payload from profiles where role = 'host' order by sort_order, id limit 1),
    'accounts', coalesce((select jsonb_agg(payload order by sort_order, id) from accounts), '[]'::jsonb),
    'trades', coalesce((select jsonb_agg(payload order by sort_order, id) from trades), '[]'::jsonb),
    'checkIns', coalesce((select jsonb_agg(payload order by sort_order, id) from check_ins), '[]'::jsonb),
    'payouts', coalesce((select jsonb_agg(payload order by sort_order, id) from payouts), '[]'::jsonb),
    'posts', coalesce((select jsonb_agg(payload order by sort_order, id) from posts), '[]'::jsonb),
    'clips', coalesce((select jsonb_agg(payload order by sort_order, id) from clips), '[]'::jsonb),
    'stories', coalesce((select jsonb_agg(payload order by sort_order, id) from stories), '[]'::jsonb),
    'achievements', coalesce((select jsonb_agg(payload order by sort_order, id) from achievements), '[]'::jsonb),
    'activity', coalesce((select jsonb_agg(payload order by sort_order, id) from activity), '[]'::jsonb),
    'conversations', coalesce((select jsonb_agg(payload order by sort_order, id) from conversations), '[]'::jsonb),
    'messages', coalesce((select jsonb_agg(payload order by sort_order, id) from messages), '[]'::jsonb),
    'room', (select payload from rooms order by sort_order, id limit 1),
    'channels', coalesce((
      select jsonb_agg(c.payload order by c.sort_order, c.id)
      from room_channels c
      where c.room_id = (select id from rooms order by sort_order, id limit 1)
    ), '[]'::jsonb),
    'memberships', coalesce((
      select jsonb_agg(m.payload order by m.sort_order, m.profile_id)
      from room_memberships m
      where m.room_id = (select id from rooms order by sort_order, id limit 1)
    ), '[]'::jsonb),
    'roomMessages', coalesce((
      select jsonb_agg(m.payload order by m.sort_order, m.id)
      from room_messages m
      where m.room_id = (select id from rooms order by sort_order, id limit 1)
    ), '[]'::jsonb),
    'vaultFolders', coalesce((select jsonb_agg(payload order by sort_order, id) from vault_folders), '[]'::jsonb),
    'vaultItems', coalesce((select jsonb_agg(payload order by sort_order, id) from vault_items), '[]'::jsonb)
  );
$fn$;

create or replace function demo.validate_snapshot(p_snapshot jsonb)
returns text[]
language plpgsql
stable
security definer
set search_path = demo, pg_temp
as $fn$
declare
  v_errors text[] := '{}';
  v_profiles text[];
  v_accounts text[];
  v_trades text[];
  v_posts text[];
  v_clips text[];
  v_achievements text[];
  v_folders text[];
  v_channels text[];
  v_room text;
begin
  if coalesce(p_snapshot->>'schemaVersion', '') <> '1' then
    v_errors := v_errors || 'Snapshot schema must stay at version 1.';
  end if;
  if coalesce(p_snapshot->'viewer'->>'id', '') <> 'demo.explore.trader' then
    v_errors := v_errors || 'The Demo viewer must stay demo.explore.trader so the native app can recognize it.';
  end if;
  if jsonb_typeof(p_snapshot->'host') <> 'object' or coalesce(p_snapshot->'host'->>'id', '') = '' then
    v_errors := v_errors || 'A Trade Room host profile is required.';
  end if;
  if jsonb_array_length(coalesce(p_snapshot->'accounts', '[]'::jsonb)) < 1 then
    v_errors := v_errors || 'Add at least one Demo account.';
  end if;
  if jsonb_array_length(coalesce(p_snapshot->'trades', '[]'::jsonb)) < 1 then
    v_errors := v_errors || 'Add at least one Demo trade.';
  end if;
  if jsonb_typeof(p_snapshot->'room') <> 'object' or coalesce(p_snapshot->'room'->>'id', '') = '' then
    v_errors := v_errors || 'A Demo Trade Room is required.';
  end if;
  if (select count(*) from rooms) > 1 then
    v_errors := v_errors || 'The published Demo snapshot includes one Trade Room. Delete the extra room before publishing.';
  end if;

  select coalesce(array_agg(id), '{}') into v_profiles from (
    select p_snapshot->'viewer'->>'id' as id
    union select p_snapshot->'host'->>'id'
    union select peer->>'id' from jsonb_array_elements(coalesce(p_snapshot->'peers', '[]'::jsonb)) peer
  ) s where id is not null and id <> '';
  select coalesce(array_agg(item->>'id'), '{}') into v_accounts from jsonb_array_elements(coalesce(p_snapshot->'accounts', '[]'::jsonb)) item;
  select coalesce(array_agg(item->>'id'), '{}') into v_trades from jsonb_array_elements(coalesce(p_snapshot->'trades', '[]'::jsonb)) item;
  select coalesce(array_agg(item->>'id'), '{}') into v_posts from jsonb_array_elements(coalesce(p_snapshot->'posts', '[]'::jsonb)) item;
  select coalesce(array_agg(item->>'id'), '{}') into v_clips from jsonb_array_elements(coalesce(p_snapshot->'clips', '[]'::jsonb)) item;
  select coalesce(array_agg(item->>'id'), '{}') into v_achievements from jsonb_array_elements(coalesce(p_snapshot->'achievements', '[]'::jsonb)) item;
  select coalesce(array_agg(item->>'id'), '{}') into v_folders from jsonb_array_elements(coalesce(p_snapshot->'vaultFolders', '[]'::jsonb)) item;
  select coalesce(array_agg(item->>'id'), '{}') into v_channels from jsonb_array_elements(coalesce(p_snapshot->'channels', '[]'::jsonb)) item;
  v_room := p_snapshot->'room'->>'id';

  v_errors := v_errors || array(
    select format('Trade %s references account %s, which does not exist.', item->>'id', item->>'accountID')
    from jsonb_array_elements(coalesce(p_snapshot->'trades', '[]'::jsonb)) item
    where coalesce(item->>'accountID', '') = '' or not (item->>'accountID' = any (v_accounts))
  );
  v_errors := v_errors || array(
    select format('Trade %s owner %s is not a Demo profile.', item->>'id', item->>'ownerProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'trades', '[]'::jsonb)) item
    where not (coalesce(item->>'ownerProfileID', '') = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Post %s author %s is not a Demo profile.', item->>'id', item->>'authorProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'posts', '[]'::jsonb)) item
    where not (coalesce(item->>'authorProfileID', '') = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Post %s references trade %s, which does not exist.', item->>'id', item->>'linkedTradeID')
    from jsonb_array_elements(coalesce(p_snapshot->'posts', '[]'::jsonb)) item
    where coalesce(item->>'linkedTradeID', '') <> '' and not (item->>'linkedTradeID' = any (v_trades))
  );
  v_errors := v_errors || array(
    select format('Clip %s author %s is not a Demo profile.', item->>'id', item->>'authorProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'clips', '[]'::jsonb)) item
    where not (coalesce(item->>'authorProfileID', '') = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Clip %s references trade %s, which does not exist.', item->>'id', item->>'linkedTradeID')
    from jsonb_array_elements(coalesce(p_snapshot->'clips', '[]'::jsonb)) item
    where coalesce(item->>'linkedTradeID', '') <> '' and not (item->>'linkedTradeID' = any (v_trades))
  );
  v_errors := v_errors || array(
    select format('Story %s author %s is not a Demo profile.', item->>'id', item->>'authorProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'stories', '[]'::jsonb)) item
    where not (coalesce(item->>'authorProfileID', '') = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Achievement %s owner %s is not a Demo profile.', item->>'id', item->>'ownerProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'achievements', '[]'::jsonb)) item
    where not (coalesce(item->>'ownerProfileID', '') = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Achievement %s references account %s, which does not exist.', item->>'id', item->>'accountID')
    from jsonb_array_elements(coalesce(p_snapshot->'achievements', '[]'::jsonb)) item
    where coalesce(item->>'accountID', '') <> '' and not (item->>'accountID' = any (v_accounts))
  );
  v_errors := v_errors || array(
    select format('Activity %s actor %s is not a Demo profile.', item->>'id', item->>'actorProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'activity', '[]'::jsonb)) item
    where coalesce(item->>'actorProfileID', '') <> '' and not (item->>'actorProfileID' = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Activity %s references trade %s, which does not exist.', item->>'id', item->>'tradeID')
    from jsonb_array_elements(coalesce(p_snapshot->'activity', '[]'::jsonb)) item
    where coalesce(item->>'tradeID', '') <> '' and not (item->>'tradeID' = any (v_trades))
  );
  v_errors := v_errors || array(
    select format('Activity %s references post %s, which does not exist.', item->>'id', item->>'postID')
    from jsonb_array_elements(coalesce(p_snapshot->'activity', '[]'::jsonb)) item
    where coalesce(item->>'postID', '') <> '' and not (item->>'postID' = any (v_posts))
  );
  v_errors := v_errors || array(
    select format('Activity %s references room %s, which is not the Demo room.', item->>'id', item->>'roomID')
    from jsonb_array_elements(coalesce(p_snapshot->'activity', '[]'::jsonb)) item
    where coalesce(item->>'roomID', '') <> '' and item->>'roomID' is distinct from v_room
  );
  v_errors := v_errors || array(
    select format('Trading report activity %s must use report monthly_last.', item->>'id')
    from jsonb_array_elements(coalesce(p_snapshot->'activity', '[]'::jsonb)) item
    where item->>'kind' = 'trading_report' and coalesce(item->>'reportID', '') <> 'monthly_last'
  );
  v_errors := v_errors || array(
    select format('Message %s sender %s is not a Demo profile.', item->>'id', item->>'senderProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'messages', '[]'::jsonb)) item
    where not (coalesce(item->>'senderProfileID', '') = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Message %s is in conversation %s, which does not exist.', item->>'id', item->>'conversationID')
    from jsonb_array_elements(coalesce(p_snapshot->'messages', '[]'::jsonb)) item
    where not exists (
      select 1 from jsonb_array_elements(coalesce(p_snapshot->'conversations', '[]'::jsonb)) c
      where c->>'id' = item->>'conversationID'
    )
  );
  v_errors := v_errors || array(
    select format('Message %s shares trade %s, which does not exist.', item->>'id', item#>>'{sharedContent,trade,_0}')
    from jsonb_array_elements(coalesce(p_snapshot->'messages', '[]'::jsonb)) item
    where coalesce(item#>>'{sharedContent,trade,_0}', '') <> ''
      and not (item#>>'{sharedContent,trade,_0}' = any (v_trades))
  );
  v_errors := v_errors || array(
    select format('Message %s shares post %s, which does not exist.', item->>'id', coalesce(item#>>'{sharedContent,feedPost,_0}', item#>>'{sharedContent,profilePost,_0}'))
    from jsonb_array_elements(coalesce(p_snapshot->'messages', '[]'::jsonb)) item
    where coalesce(item#>>'{sharedContent,feedPost,_0}', item#>>'{sharedContent,profilePost,_0}', '') <> ''
      and not (coalesce(item#>>'{sharedContent,feedPost,_0}', item#>>'{sharedContent,profilePost,_0}') = any (v_posts))
  );
  v_errors := v_errors || array(
    select format('Message %s shares achievement %s, which does not exist.', item->>'id', item#>>'{sharedContent,achievementPost,_0}')
    from jsonb_array_elements(coalesce(p_snapshot->'messages', '[]'::jsonb)) item
    where coalesce(item#>>'{sharedContent,achievementPost,_0}', '') <> ''
      and not (item#>>'{sharedContent,achievementPost,_0}' = any (v_achievements))
  );
  v_errors := v_errors || array(
    select format('Message %s shares clip %s, which does not exist.', item->>'id', item#>>'{sharedContent,reel,_0}')
    from jsonb_array_elements(coalesce(p_snapshot->'messages', '[]'::jsonb)) item
    where coalesce(item#>>'{sharedContent,reel,_0}', '') <> ''
      and not (item#>>'{sharedContent,reel,_0}' = any (v_clips))
  );
  v_errors := v_errors || array(
    select format('Conversation %s includes profile %s, which does not exist.', c->>'id', participant)
    from jsonb_array_elements(coalesce(p_snapshot->'conversations', '[]'::jsonb)) c
    cross join lateral jsonb_array_elements_text(coalesce(c->'participantProfileIDs', '[]'::jsonb)) participant
    where not (participant = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Room member %s is not a Demo profile.', item->>'profileID')
    from jsonb_array_elements(coalesce(p_snapshot->'memberships', '[]'::jsonb)) item
    where not (coalesce(item->>'profileID', '') = any (v_profiles))
       or item->>'roomID' is distinct from v_room
  );
  v_errors := v_errors || array(
    select format('Room message %s sender %s is not a Demo profile.', item->>'id', item->>'senderProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'roomMessages', '[]'::jsonb)) item
    where not (coalesce(item->>'senderProfileID', '') = any (v_profiles))
       or item->>'roomID' is distinct from v_room
  );
  v_errors := v_errors || array(
    select format('Room message %s uses channel %s, which does not exist.', item->>'id', item->>'channelID')
    from jsonb_array_elements(coalesce(p_snapshot->'roomMessages', '[]'::jsonb)) item
    where coalesce(item->>'channelID', '') <> '' and not (item->>'channelID' = any (v_channels))
  );
  v_errors := v_errors || array(
    select format('Room message %s shares trade %s, which does not exist.', item->>'id', item->>'attachedTradeID')
    from jsonb_array_elements(coalesce(p_snapshot->'roomMessages', '[]'::jsonb)) item
    where coalesce(item->>'attachedTradeID', '') <> '' and not (item->>'attachedTradeID' = any (v_trades))
  );
  v_errors := v_errors || array(
    select format('Payout %s references account %s, which does not exist.', item->>'id', item->>'accountID')
    from jsonb_array_elements(coalesce(p_snapshot->'payouts', '[]'::jsonb)) item
    where not (coalesce(item->>'accountID', '') = any (v_accounts))
  );
  v_errors := v_errors || array(
    select format('Check-in %s owner %s is not a Demo profile.', item->>'id', item->>'ownerProfileID')
    from jsonb_array_elements(coalesce(p_snapshot->'checkIns', '[]'::jsonb)) item
    where not (coalesce(item->>'ownerProfileID', '') = any (v_profiles))
  );
  v_errors := v_errors || array(
    select format('Check-in %s has stress %s. Use 1 (calm) through 5 (very stressed).', item->>'id', item->>'stressLevel')
    from jsonb_array_elements(coalesce(p_snapshot->'checkIns', '[]'::jsonb)) item
    where item ? 'stressLevel'
      and item->>'stressLevel' is not null
      and (item->>'stressLevel') !~ '^[1-5]$'
  );
  v_errors := v_errors || array(
    select format('Vault item %s references trade %s, which does not exist.', item->>'id', item#>>'{ref,contentID}')
    from jsonb_array_elements(coalesce(p_snapshot->'vaultItems', '[]'::jsonb)) item
    where item#>>'{ref,contentType}' = 'trade'
      and not (coalesce(item#>>'{ref,contentID}', '') = any (v_trades))
  );
  v_errors := v_errors || array(
    select format('Vault item %s references post %s, which does not exist.', item->>'id', item#>>'{ref,contentID}')
    from jsonb_array_elements(coalesce(p_snapshot->'vaultItems', '[]'::jsonb)) item
    where item#>>'{ref,contentType}' in ('profile_post', 'feed_post')
      and not (coalesce(item#>>'{ref,contentID}', '') = any (v_posts))
  );
  v_errors := v_errors || array(
    select format('Vault item %s references clip %s, which does not exist.', item->>'id', item#>>'{ref,contentID}')
    from jsonb_array_elements(coalesce(p_snapshot->'vaultItems', '[]'::jsonb)) item
    where item#>>'{ref,contentType}' = 'reel'
      and not (coalesce(item#>>'{ref,contentID}', '') = any (v_clips))
  );
  v_errors := v_errors || array(
    select format('Vault item %s references achievement %s, which does not exist.', item->>'id', item#>>'{ref,contentID}')
    from jsonb_array_elements(coalesce(p_snapshot->'vaultItems', '[]'::jsonb)) item
    where item#>>'{ref,contentType}' = 'achievement'
      and not (coalesce(item#>>'{ref,contentID}', '') = any (v_achievements))
  );
  v_errors := v_errors || array(
    select format('Vault item %s is in folder %s, which does not exist.', item->>'id', folder)
    from jsonb_array_elements(coalesce(p_snapshot->'vaultItems', '[]'::jsonb)) item
    cross join lateral jsonb_array_elements_text(coalesce(item->'folderIDs', '[]'::jsonb)) folder
    where not (folder = any (v_folders))
  );
  return v_errors;
end;
$fn$;

create or replace function demo.replace_entities_from_snapshot(p_snapshot jsonb)
returns void
language plpgsql
security definer
set search_path = demo, pg_temp
as $fn$
begin
  delete from room_messages;
  delete from room_memberships;
  delete from room_channels;
  delete from messages;
  delete from rooms;
  delete from conversations;
  delete from activity;
  delete from achievements;
  delete from stories;
  delete from clips;
  delete from posts;
  delete from payouts;
  delete from check_ins;
  delete from trades;
  delete from accounts;
  delete from vault_items;
  delete from vault_folders;
  delete from profiles;

  insert into profiles (id, role, payload, sort_order)
  select p_snapshot->'viewer'->>'id', 'viewer', p_snapshot->'viewer', 0
  where coalesce(p_snapshot->'viewer'->>'id', '') <> '';

  insert into profiles (id, role, payload, sort_order)
  select peer->>'id', 'peer', peer, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'peers', '[]'::jsonb)) with ordinality as t(peer, ordinality)
  where coalesce(peer->>'id', '') <> '';

  insert into profiles (id, role, payload, sort_order)
  select p_snapshot->'host'->>'id', 'host', p_snapshot->'host', 0
  where coalesce(p_snapshot->'host'->>'id', '') <> ''
    and p_snapshot->'host'->>'id' is distinct from p_snapshot->'viewer'->>'id'
  on conflict (id) do update set role = 'host', payload = excluded.payload;

  insert into accounts (id, owner_profile_id, payload, sort_order)
  select item->>'id', item->>'ownerProfileID', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'accounts', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into trades (id, account_id, owner_profile_id, payload, sort_order)
  select item->>'id', item->>'accountID', item->>'ownerProfileID', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'trades', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into check_ins (id, owner_profile_id, payload, sort_order)
  select item->>'id', item->>'ownerProfileID', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'checkIns', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into payouts (id, account_id, payload, sort_order)
  select item->>'id', item->>'accountID', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'payouts', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into posts (id, author_profile_id, linked_trade_id, payload, sort_order)
  select item->>'id', item->>'authorProfileID', nullif(item->>'linkedTradeID', ''), item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'posts', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into clips (id, author_profile_id, linked_trade_id, payload, sort_order)
  select item->>'id', item->>'authorProfileID', nullif(item->>'linkedTradeID', ''), item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'clips', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into stories (id, author_profile_id, payload, sort_order)
  select item->>'id', item->>'authorProfileID', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'stories', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into achievements (id, owner_profile_id, account_id, payload, sort_order)
  select item->>'id', item->>'ownerProfileID', nullif(item->>'accountID', ''), item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'achievements', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into activity (id, actor_profile_id, trade_id, payload, sort_order)
  select item->>'id', nullif(item->>'actorProfileID', ''), nullif(item->>'tradeID', ''), item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'activity', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into conversations (id, payload, sort_order)
  select item->>'id', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'conversations', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into messages (id, conversation_id, sender_profile_id, payload, sort_order)
  select item->>'id', item->>'conversationID', item->>'senderProfileID', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'messages', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into rooms (id, payload, sort_order)
  select p_snapshot->'room'->>'id', p_snapshot->'room', 0
  where coalesce(p_snapshot->'room'->>'id', '') <> '';

  insert into room_channels (id, room_id, payload, sort_order)
  select item->>'id', item->>'roomID', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'channels', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into room_memberships (room_id, profile_id, role, payload, sort_order)
  select item->>'roomID', item->>'profileID', item->>'role', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'memberships', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into room_messages (id, room_id, channel_id, sender_profile_id, payload, sort_order)
  select item->>'id', item->>'roomID', nullif(item->>'channelID', ''), item->>'senderProfileID', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'roomMessages', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into vault_folders (id, payload, sort_order)
  select item->>'id', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'vaultFolders', '[]'::jsonb)) with ordinality as t(item, ordinality);

  insert into vault_items (id, payload, sort_order)
  select item->>'id', item, (ordinality - 1)::integer
  from jsonb_array_elements(coalesce(p_snapshot->'vaultItems', '[]'::jsonb)) with ordinality as t(item, ordinality);
end;
$fn$;

create or replace function demo.admin_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = demo, public, pg_temp
as $fn$
declare
  v_current jsonb;
  v_version integer;
  v_published_at text;
  v_assembled jsonb;
begin
  select snapshot, version, snapshot->>'publishedAt'
    into v_current, v_version, v_published_at
  from publications
  where is_current
  order by version desc
  limit 1;

  if v_current is null then
    v_assembled := assemble_draft(1, to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  else
    v_assembled := assemble_draft(v_version, v_published_at);
  end if;

  return jsonb_build_object(
    'ok', true,
    'dirty', v_current is null or v_assembled is distinct from v_current,
    'published', (
      select jsonb_build_object(
        'version', version,
        'publishedAt', snapshot->>'publishedAt',
        'publisherEmail', publisher_email,
        'restoredFrom', restored_from,
        'isCurrent', true
      )
      from publications
      where is_current
      order by version desc
      limit 1
    ),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'version', version,
        'publishedAt', snapshot->>'publishedAt',
        'publisherEmail', publisher_email,
        'restoredFrom', restored_from,
        'isCurrent', is_current
      ) order by version desc)
      from publications
    ), '[]'::jsonb),
    'draft', jsonb_build_object(
      'profiles', coalesce((select jsonb_agg(jsonb_build_object('role', role, 'record', payload) order by role, sort_order, id) from profiles), '[]'::jsonb),
      'accounts', coalesce((select jsonb_agg(payload order by sort_order, id) from accounts), '[]'::jsonb),
      'trades', coalesce((select jsonb_agg(payload order by sort_order, id) from trades), '[]'::jsonb),
      'posts', coalesce((select jsonb_agg(payload order by sort_order, id) from posts), '[]'::jsonb),
      'clips', coalesce((select jsonb_agg(payload order by sort_order, id) from clips), '[]'::jsonb),
      'stories', coalesce((select jsonb_agg(payload order by sort_order, id) from stories), '[]'::jsonb),
      'achievements', coalesce((select jsonb_agg(payload order by sort_order, id) from achievements), '[]'::jsonb),
      'activity', coalesce((select jsonb_agg(payload order by sort_order, id) from activity), '[]'::jsonb),
      'conversations', coalesce((select jsonb_agg(payload order by sort_order, id) from conversations), '[]'::jsonb),
      'messages', coalesce((select jsonb_agg(payload order by sort_order, id) from messages), '[]'::jsonb),
      'rooms', coalesce((select jsonb_agg(payload order by sort_order, id) from rooms), '[]'::jsonb),
      'channels', coalesce((select jsonb_agg(payload order by sort_order, id) from room_channels), '[]'::jsonb),
      'memberships', coalesce((select jsonb_agg(payload order by sort_order, profile_id) from room_memberships), '[]'::jsonb),
      'roomMessages', coalesce((select jsonb_agg(payload order by sort_order, id) from room_messages), '[]'::jsonb),
      'checkIns', coalesce((select jsonb_agg(payload order by sort_order, id) from check_ins), '[]'::jsonb),
      'payouts', coalesce((select jsonb_agg(payload order by sort_order, id) from payouts), '[]'::jsonb),
      'vaultFolders', coalesce((select jsonb_agg(payload order by sort_order, id) from vault_folders), '[]'::jsonb),
      'vaultItems', coalesce((select jsonb_agg(payload order by sort_order, id) from vault_items), '[]'::jsonb)
    )
  );
end;
$fn$;

create or replace function demo.admin_next_sort(p_table text)
returns integer
language plpgsql
security definer
set search_path = demo, pg_temp
as $fn$
declare
  v_next integer;
begin
  execute format('select coalesce(max(sort_order), -1) + 1 from demo.%I', p_table) into v_next;
  return v_next;
end;
$fn$;

create or replace function demo.admin_save(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = demo, pg_temp
as $fn$
declare
  v_entity text := p_payload->>'entity';
  v_record jsonb := p_payload->'record';
  v_id text := coalesce(v_record->>'id', '');
  v_role text;
begin
  if v_entity = 'membership' then
    if coalesce(v_record->>'roomID', '') = '' or coalesce(v_record->>'profileID', '') = '' then
      return jsonb_build_object('ok', false, 'error', 'Choose a room and a profile for this member.');
    end if;
    insert into room_memberships (room_id, profile_id, role, payload, sort_order)
    values (
      v_record->>'roomID',
      v_record->>'profileID',
      coalesce(v_record->>'role', 'member'),
      v_record,
      coalesce((select sort_order from room_memberships where room_id = v_record->>'roomID' and profile_id = v_record->>'profileID'), admin_next_sort('room_memberships'))
    )
    on conflict (room_id, profile_id) do update set role = excluded.role, payload = excluded.payload;
    return admin_state();
  end if;

  if v_record is null or v_id = '' then
    return jsonb_build_object('ok', false, 'error', 'A record id is required.');
  end if;

  if v_entity = 'profile' then
    select role into v_role from profiles where id = v_id;
    v_role := coalesce(p_payload->>'role', v_role, 'peer');
    if v_id = 'demo.explore.trader' then
      v_role := 'viewer';
    elsif v_role = 'viewer' then
      return jsonb_build_object('ok', false, 'error', 'The Demo viewer id cannot be reassigned.');
    end if;
    if exists (select 1 from profiles where id = v_id and role = 'host') and v_role <> 'host' and v_id <> 'demo.explore.trader' then
      v_role := 'host';
    end if;
    insert into profiles (id, role, payload, sort_order)
    values (v_id, v_role, v_record, coalesce((select sort_order from profiles where id = v_id), admin_next_sort('profiles')))
    on conflict (id) do update set role = excluded.role, payload = excluded.payload;
    return admin_state();
  elsif v_entity = 'account' then
    insert into accounts (id, owner_profile_id, payload, sort_order)
    values (v_id, v_record->>'ownerProfileID', v_record, coalesce((select sort_order from accounts where id = v_id), admin_next_sort('accounts')))
    on conflict (id) do update set owner_profile_id = excluded.owner_profile_id, payload = excluded.payload;
  elsif v_entity = 'trade' then
    insert into trades (id, account_id, owner_profile_id, payload, sort_order)
    values (v_id, v_record->>'accountID', v_record->>'ownerProfileID', v_record, coalesce((select sort_order from trades where id = v_id), admin_next_sort('trades')))
    on conflict (id) do update set account_id = excluded.account_id, owner_profile_id = excluded.owner_profile_id, payload = excluded.payload;
  elsif v_entity = 'post' then
    insert into posts (id, author_profile_id, linked_trade_id, payload, sort_order)
    values (v_id, v_record->>'authorProfileID', nullif(v_record->>'linkedTradeID', ''), v_record, coalesce((select sort_order from posts where id = v_id), admin_next_sort('posts')))
    on conflict (id) do update set author_profile_id = excluded.author_profile_id, linked_trade_id = excluded.linked_trade_id, payload = excluded.payload;
  elsif v_entity = 'clip' then
    insert into clips (id, author_profile_id, linked_trade_id, payload, sort_order)
    values (v_id, v_record->>'authorProfileID', nullif(v_record->>'linkedTradeID', ''), v_record, coalesce((select sort_order from clips where id = v_id), admin_next_sort('clips')))
    on conflict (id) do update set author_profile_id = excluded.author_profile_id, linked_trade_id = excluded.linked_trade_id, payload = excluded.payload;
  elsif v_entity = 'story' then
    insert into stories (id, author_profile_id, payload, sort_order)
    values (v_id, v_record->>'authorProfileID', v_record, coalesce((select sort_order from stories where id = v_id), admin_next_sort('stories')))
    on conflict (id) do update set author_profile_id = excluded.author_profile_id, payload = excluded.payload;
  elsif v_entity = 'achievement' then
    insert into achievements (id, owner_profile_id, account_id, payload, sort_order)
    values (v_id, v_record->>'ownerProfileID', nullif(v_record->>'accountID', ''), v_record, coalesce((select sort_order from achievements where id = v_id), admin_next_sort('achievements')))
    on conflict (id) do update set owner_profile_id = excluded.owner_profile_id, account_id = excluded.account_id, payload = excluded.payload;
  elsif v_entity = 'activity' then
    insert into activity (id, actor_profile_id, trade_id, payload, sort_order)
    values (v_id, nullif(v_record->>'actorProfileID', ''), nullif(v_record->>'tradeID', ''), v_record, coalesce((select sort_order from activity where id = v_id), admin_next_sort('activity')))
    on conflict (id) do update set actor_profile_id = excluded.actor_profile_id, trade_id = excluded.trade_id, payload = excluded.payload;
  elsif v_entity = 'conversation' then
    insert into conversations (id, payload, sort_order)
    values (v_id, v_record, coalesce((select sort_order from conversations where id = v_id), admin_next_sort('conversations')))
    on conflict (id) do update set payload = excluded.payload;
  elsif v_entity = 'message' then
    insert into messages (id, conversation_id, sender_profile_id, payload, sort_order)
    values (v_id, v_record->>'conversationID', v_record->>'senderProfileID', v_record, coalesce((select sort_order from messages where id = v_id), admin_next_sort('messages')))
    on conflict (id) do update set conversation_id = excluded.conversation_id, sender_profile_id = excluded.sender_profile_id, payload = excluded.payload;
  elsif v_entity = 'room' then
    if exists (select 1 from rooms where id <> v_id) and not exists (select 1 from rooms where id = v_id) then
      return jsonb_build_object('ok', false, 'error', 'The published Demo snapshot includes one Trade Room. Edit the existing room.');
    end if;
    insert into rooms (id, payload, sort_order)
    values (v_id, v_record, coalesce((select sort_order from rooms where id = v_id), 0))
    on conflict (id) do update set payload = excluded.payload;
  elsif v_entity = 'channel' then
    insert into room_channels (id, room_id, payload, sort_order)
    values (v_id, v_record->>'roomID', v_record, coalesce((select sort_order from room_channels where id = v_id), admin_next_sort('room_channels')))
    on conflict (id) do update set room_id = excluded.room_id, payload = excluded.payload;
  elsif v_entity = 'room_message' then
    insert into room_messages (id, room_id, channel_id, sender_profile_id, payload, sort_order)
    values (v_id, v_record->>'roomID', nullif(v_record->>'channelID', ''), v_record->>'senderProfileID', v_record, coalesce((select sort_order from room_messages where id = v_id), admin_next_sort('room_messages')))
    on conflict (id) do update set room_id = excluded.room_id, channel_id = excluded.channel_id, sender_profile_id = excluded.sender_profile_id, payload = excluded.payload;
  elsif v_entity = 'check_in' then
    insert into check_ins (id, owner_profile_id, payload, sort_order)
    values (v_id, v_record->>'ownerProfileID', v_record, coalesce((select sort_order from check_ins where id = v_id), admin_next_sort('check_ins')))
    on conflict (id) do update set owner_profile_id = excluded.owner_profile_id, payload = excluded.payload;
  elsif v_entity = 'payout' then
    insert into payouts (id, account_id, payload, sort_order)
    values (v_id, v_record->>'accountID', v_record, coalesce((select sort_order from payouts where id = v_id), admin_next_sort('payouts')))
    on conflict (id) do update set account_id = excluded.account_id, payload = excluded.payload;
  elsif v_entity = 'vault_folder' then
    insert into vault_folders (id, payload, sort_order)
    values (v_id, v_record, coalesce((select sort_order from vault_folders where id = v_id), admin_next_sort('vault_folders')))
    on conflict (id) do update set payload = excluded.payload;
  elsif v_entity = 'vault_item' then
    insert into vault_items (id, payload, sort_order)
    values (v_id, v_record, coalesce((select sort_order from vault_items where id = v_id), admin_next_sort('vault_items')))
    on conflict (id) do update set payload = excluded.payload;
  else
    return jsonb_build_object('ok', false, 'error', 'Unknown Demo record.');
  end if;

  return admin_state();
end;
$fn$;

create or replace function demo.admin_delete(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = demo, pg_temp
as $fn$
declare
  v_entity text := p_payload->>'entity';
  v_id text := coalesce(p_payload->>'id', '');
  v_room text := coalesce(p_payload->>'roomID', '');
  v_profile text := coalesce(p_payload->>'profileID', '');
  v_name text;
  v_count integer;
begin
  if v_entity = 'profile' then
    if v_id = 'demo.explore.trader' or exists (select 1 from profiles where id = v_id and role = 'viewer') then
      return jsonb_build_object('ok', false, 'error', 'The Demo viewer profile is required.');
    end if;
    if exists (select 1 from profiles where id = v_id and role = 'host') then
      return jsonb_build_object('ok', false, 'error', 'The Trade Room host profile is required. Edit it instead of deleting it.');
    end if;
    select count(*) into v_count from trades where owner_profile_id = v_id;
    if v_count > 0 then
      return jsonb_build_object('ok', false, 'error', format('This profile still owns %s trade(s). Reassign those trades first.', v_count));
    end if;
    select count(*) into v_count from posts where author_profile_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This profile still authors %s post(s).', v_count)); end if;
    select count(*) into v_count from clips where author_profile_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This profile still authors %s clip(s).', v_count)); end if;
    select count(*) into v_count from stories where author_profile_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This profile still has %s story(s).', v_count)); end if;
    select count(*) into v_count from messages where sender_profile_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This profile still sends %s message(s).', v_count)); end if;
    select count(*) into v_count from room_messages where sender_profile_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This profile still sends %s room message(s).', v_count)); end if;
    select count(*) into v_count from room_memberships where profile_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', 'Remove this profile from the Trade Room before deleting it.'); end if;
    select count(*) into v_count from activity where actor_profile_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This profile is the actor on %s activity item(s).', v_count)); end if;
    select count(*) into v_count from conversations where payload->'participantProfileIDs' ? v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', 'This profile is still in a conversation.'); end if;
    delete from profiles where id = v_id and role = 'peer';
  elsif v_entity = 'account' then
    select payload->>'name' into v_name from accounts where id = v_id;
    select count(*) into v_count from trades where account_id = v_id;
    if v_count > 0 then
      return jsonb_build_object('ok', false, 'error', format('%s still has %s trade(s). Move or delete those trades before deleting this account.', coalesce(v_name, 'This account'), v_count));
    end if;
    select count(*) into v_count from payouts where account_id = v_id;
    if v_count > 0 then
      return jsonb_build_object('ok', false, 'error', format('%s still has %s payout(s).', coalesce(v_name, 'This account'), v_count));
    end if;
    select count(*) into v_count from achievements where account_id = v_id;
    if v_count > 0 then
      return jsonb_build_object('ok', false, 'error', format('%s is still linked to %s achievement(s).', coalesce(v_name, 'This account'), v_count));
    end if;
    delete from accounts where id = v_id;
  elsif v_entity = 'trade' then
    select count(*) into v_count from posts where linked_trade_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This trade is linked from %s post(s).', v_count)); end if;
    select count(*) into v_count from clips where linked_trade_id = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This trade is linked from %s clip(s).', v_count)); end if;
    select count(*) into v_count from activity where trade_id = v_id or payload->>'tradeID' = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', format('This trade is the target of %s activity item(s).', v_count)); end if;
    select count(*) into v_count from messages where payload#>>'{sharedContent,trade,_0}' = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', 'A message still shares this trade.'); end if;
    select count(*) into v_count from room_messages where payload->>'attachedTradeID' = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', 'A room message still shares this trade.'); end if;
    select count(*) into v_count from vault_items where payload#>>'{ref,contentType}' = 'trade' and payload#>>'{ref,contentID}' = v_id;
    if v_count > 0 then return jsonb_build_object('ok', false, 'error', 'The Vault still saves this trade.'); end if;
    delete from trades where id = v_id;
  elsif v_entity = 'post' then
    if exists (select 1 from activity where payload->>'postID' = v_id)
      or exists (select 1 from messages where payload#>>'{sharedContent,feedPost,_0}' = v_id or payload#>>'{sharedContent,profilePost,_0}' = v_id)
      or exists (select 1 from vault_items where payload#>>'{ref,contentID}' = v_id and payload#>>'{ref,contentType}' in ('profile_post', 'feed_post')) then
      return jsonb_build_object('ok', false, 'error', 'Activity, messages, or Vault items still reference this post.');
    end if;
    delete from posts where id = v_id;
  elsif v_entity = 'clip' then
    if exists (select 1 from messages where payload#>>'{sharedContent,reel,_0}' = v_id)
      or exists (select 1 from vault_items where payload#>>'{ref,contentType}' = 'reel' and payload#>>'{ref,contentID}' = v_id) then
      return jsonb_build_object('ok', false, 'error', 'A message or Vault item still references this clip.');
    end if;
    delete from clips where id = v_id;
  elsif v_entity = 'story' then
    delete from stories where id = v_id;
  elsif v_entity = 'achievement' then
    if exists (select 1 from vault_items where payload#>>'{ref,contentType}' = 'achievement' and payload#>>'{ref,contentID}' = v_id)
      or exists (select 1 from messages where payload#>>'{sharedContent,achievementPost,_0}' = v_id) then
      return jsonb_build_object('ok', false, 'error', 'A message or Vault item still references this achievement.');
    end if;
    delete from achievements where id = v_id;
  elsif v_entity = 'activity' then
    delete from activity where id = v_id;
  elsif v_entity = 'conversation' then
    select count(*) into v_count from messages where conversation_id = v_id;
    if v_count > 0 then
      return jsonb_build_object('ok', false, 'error', format('This conversation still has %s message(s). Delete those messages first.', v_count));
    end if;
    delete from conversations where id = v_id;
  elsif v_entity = 'message' then
    delete from messages where id = v_id;
  elsif v_entity = 'room' then
    delete from room_messages where room_id = v_id;
    delete from room_memberships where room_id = v_id;
    delete from room_channels where room_id = v_id;
    delete from rooms where id = v_id;
  elsif v_entity = 'channel' then
    if exists (select 1 from room_messages where channel_id = v_id) then
      return jsonb_build_object('ok', false, 'error', 'Move or delete the messages in this channel first.');
    end if;
    delete from room_channels where id = v_id;
  elsif v_entity = 'membership' then
    if exists (select 1 from room_memberships where room_id = v_room and profile_id = v_profile and role = 'owner') then
      return jsonb_build_object('ok', false, 'error', 'The room owner stays a member. Change the room owner first.');
    end if;
    delete from room_memberships where room_id = v_room and profile_id = v_profile;
  elsif v_entity = 'room_message' then
    delete from room_messages where id = v_id;
  elsif v_entity = 'check_in' then
    delete from check_ins where id = v_id;
  elsif v_entity = 'payout' then
    delete from payouts where id = v_id;
  elsif v_entity = 'vault_folder' then
    if exists (
      select 1 from vault_items
      where payload->'folderIDs' ? v_id
    ) then
      return jsonb_build_object('ok', false, 'error', 'Move the saved items out of this folder before deleting it.');
    end if;
    delete from vault_folders where id = v_id;
  elsif v_entity = 'vault_item' then
    delete from vault_items where id = v_id;
  else
    return jsonb_build_object('ok', false, 'error', 'Unknown Demo record.');
  end if;
  return admin_state();
end;
$fn$;

create or replace function demo.admin_reorder(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = demo, pg_temp
as $fn$
declare
  v_entity text := p_payload->>'entity';
  v_item jsonb;
  v_index integer := 0;
begin
  if v_entity = 'account' then
    for v_item in select value from jsonb_array_elements(coalesce(p_payload->'ids', '[]'::jsonb))
    loop
      update accounts set sort_order = v_index where id = trim(both '"' from v_item::text);
      v_index := v_index + 1;
    end loop;
  elsif v_entity = 'vault_folder' then
    for v_item in select value from jsonb_array_elements(coalesce(p_payload->'ids', '[]'::jsonb))
    loop
      update vault_folders set sort_order = v_index where id = trim(both '"' from v_item::text);
      v_index := v_index + 1;
    end loop;
  elsif v_entity = 'vault_item' then
    for v_item in select value from jsonb_array_elements(coalesce(p_payload->'ids', '[]'::jsonb))
    loop
      update vault_items set sort_order = v_index where id = trim(both '"' from v_item::text);
      v_index := v_index + 1;
    end loop;
  else
    return jsonb_build_object('ok', false, 'error', 'This list cannot be reordered.');
  end if;
  return admin_state();
end;
$fn$;

create or replace function demo.admin_publish(p_restored_from integer default null)
returns jsonb
language plpgsql
security definer
set search_path = demo, public, pg_temp
as $fn$
declare
  v_errors text[];
  v_next integer;
  v_at text;
  v_snapshot jsonb;
  v_email text;
begin
  lock table publications in exclusive mode;
  v_next := coalesce((select max(version) from publications), 0) + 1;
  v_at := to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_snapshot := assemble_draft(v_next, v_at);
  v_errors := validate_snapshot(v_snapshot);
  if coalesce(array_length(v_errors, 1), 0) > 0 then
    return jsonb_build_object('ok', false, 'errors', to_jsonb(v_errors));
  end if;
  select email into v_email from auth.users where id = auth.uid();
  update publications set is_current = false where is_current;
  insert into publications (version, schema_version, published_at, snapshot, is_current, published_by, publisher_email, restored_from)
  values (v_next, 1, clock_timestamp(), v_snapshot, true, auth.uid(), v_email, p_restored_from);
  return admin_state() || jsonb_build_object('publishedVersion', v_next);
end;
$fn$;

create or replace function demo.admin_command(p_command text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = demo, public, pg_temp
as $fn$
declare
  v_version integer;
  v_snapshot jsonb;
begin
  if auth.uid() is null or not exists (select 1 from public.admin_users where user_id = auth.uid()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if p_command = 'state' then
    return admin_state();
  elsif p_command = 'validate' then
    return jsonb_build_object(
      'ok', true,
      'errors', to_jsonb(validate_snapshot(assemble_draft(1, '1970-01-01T00:00:00.000Z')))
    );
  elsif p_command = 'save' then
    return admin_save(p_payload);
  elsif p_command = 'delete' then
    return admin_delete(p_payload);
  elsif p_command = 'reorder' then
    return admin_reorder(p_payload);
  elsif p_command = 'publish' then
    return admin_publish(null);
  elsif p_command = 'discard' then
    select snapshot into v_snapshot from publications where is_current order by version desc limit 1;
    if v_snapshot is null then
      return jsonb_build_object('ok', false, 'error', 'There is no published Demo version to restore the draft from.');
    end if;
    perform replace_entities_from_snapshot(v_snapshot);
    return admin_state();
  elsif p_command = 'restore' then
    v_version := nullif(p_payload->>'version', '')::integer;
    select snapshot into v_snapshot from publications where version = v_version;
    if v_snapshot is null then
      return jsonb_build_object('ok', false, 'error', 'That Demo version does not exist.');
    end if;
    perform replace_entities_from_snapshot(v_snapshot);
    return admin_publish(v_version);
  else
    return jsonb_build_object('ok', false, 'error', 'Unknown Demo command.');
  end if;
end;
$fn$;

revoke all on function demo.assemble_draft(integer, text) from public, anon, authenticated;
revoke all on function demo.validate_snapshot(jsonb) from public, anon, authenticated;
revoke all on function demo.replace_entities_from_snapshot(jsonb) from public, anon, authenticated;
revoke all on function demo.admin_state() from public, anon, authenticated;
revoke all on function demo.admin_next_sort(text) from public, anon, authenticated;
revoke all on function demo.admin_save(jsonb) from public, anon, authenticated;
revoke all on function demo.admin_delete(jsonb) from public, anon, authenticated;
revoke all on function demo.admin_reorder(jsonb) from public, anon, authenticated;
revoke all on function demo.admin_publish(integer) from public, anon, authenticated;
revoke all on function demo.admin_command(text, jsonb) from public, anon, authenticated;

create or replace function public.rpc_v1_admin_demo(p_command text, p_payload jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = demo, public, pg_temp
as $fn$
begin
  if auth.uid() is null or not exists (select 1 from public.admin_users where user_id = auth.uid()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return demo.admin_command(p_command, coalesce(p_payload, '{}'::jsonb));
end;
$fn$;

revoke all on function public.rpc_v1_admin_demo(text, jsonb) from public, anon;
grant execute on function public.rpc_v1_admin_demo(text, jsonb) to authenticated;

comment on function public.rpc_v1_admin_demo(text, jsonb) is
  'Admin-only Demo draft editor. Visitors cannot execute it. Published reads stay on rpc_v1_demo_snapshot.';
