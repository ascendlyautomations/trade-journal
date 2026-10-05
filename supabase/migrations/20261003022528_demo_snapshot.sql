-- Isolated, versioned Demo snapshot.
-- Visitors can execute only public.rpc_v1_demo_snapshot().
-- That function returns the current published JSON document.
-- Demo tables stay out of the Data API and have no anon/authenticated grants.

create schema if not exists demo;

revoke all on schema demo from public;
revoke all on schema demo from anon, authenticated;

comment on schema demo is
  'Read-only published Demo Mode content. Not a production user schema.';

create table demo.profiles (
  id text primary key,
  role text not null check (role in ('viewer', 'peer', 'host')),
  payload jsonb not null
);

create table demo.accounts (
  id text primary key,
  owner_profile_id text not null,
  payload jsonb not null
);

create table demo.trades (
  id text primary key,
  account_id text not null,
  owner_profile_id text not null,
  payload jsonb not null
);

create table demo.check_ins (
  id text primary key,
  owner_profile_id text not null,
  payload jsonb not null
);

create table demo.payouts (
  id text primary key,
  account_id text not null,
  payload jsonb not null
);

create table demo.posts (
  id text primary key,
  author_profile_id text not null,
  linked_trade_id text,
  payload jsonb not null
);

create table demo.clips (
  id text primary key,
  author_profile_id text not null,
  linked_trade_id text,
  payload jsonb not null
);

create table demo.stories (
  id text primary key,
  author_profile_id text not null,
  payload jsonb not null
);

create table demo.achievements (
  id text primary key,
  owner_profile_id text not null,
  account_id text,
  payload jsonb not null
);

create table demo.activity (
  id text primary key,
  actor_profile_id text,
  trade_id text,
  payload jsonb not null
);

create table demo.conversations (
  id text primary key,
  payload jsonb not null
);

create table demo.messages (
  id text primary key,
  conversation_id text not null,
  sender_profile_id text not null,
  payload jsonb not null
);

create table demo.rooms (
  id text primary key,
  payload jsonb not null
);

create table demo.room_channels (
  id text primary key,
  room_id text not null,
  payload jsonb not null
);

create table demo.room_memberships (
  room_id text not null,
  profile_id text not null,
  role text not null,
  payload jsonb not null,
  primary key (room_id, profile_id)
);

create table demo.room_messages (
  id text primary key,
  room_id text not null,
  channel_id text,
  sender_profile_id text not null,
  payload jsonb not null
);

create table demo.vault_folders (
  id text primary key,
  payload jsonb not null
);

create table demo.vault_items (
  id text primary key,
  payload jsonb not null
);

create table demo.publications (
  version integer primary key check (version >= 1),
  schema_version integer not null check (schema_version >= 1),
  published_at timestamptz not null,
  snapshot jsonb not null,
  is_current boolean not null default false,
  constraint demo_publications_snapshot_version check (
    (snapshot->>'version')::integer = version
    and (snapshot->>'schemaVersion')::integer = schema_version
  )
);

create unique index demo_publications_one_current
  on demo.publications (is_current)
  where is_current;

comment on table demo.publications is
  'Point-in-time Demo documents. Visitors read is_current through the RPC, not this table.';

alter table demo.profiles enable row level security;
alter table demo.accounts enable row level security;
alter table demo.trades enable row level security;
alter table demo.check_ins enable row level security;
alter table demo.payouts enable row level security;
alter table demo.posts enable row level security;
alter table demo.clips enable row level security;
alter table demo.stories enable row level security;
alter table demo.achievements enable row level security;
alter table demo.activity enable row level security;
alter table demo.conversations enable row level security;
alter table demo.messages enable row level security;
alter table demo.rooms enable row level security;
alter table demo.room_channels enable row level security;
alter table demo.room_memberships enable row level security;
alter table demo.room_messages enable row level security;
alter table demo.vault_folders enable row level security;
alter table demo.vault_items enable row level security;
alter table demo.publications enable row level security;

revoke all on all tables in schema demo from public, anon, authenticated;
grant all on all tables in schema demo to service_role;

-- Privileged read stays in the unexposed demo schema.
create or replace function demo.current_published_snapshot()
returns jsonb
language sql
stable
security definer
set search_path = demo, pg_temp
as $$
  select snapshot
  from publications
  where is_current
  order by version desc
  limit 1;
$$;

revoke all on function demo.current_published_snapshot() from public, anon, authenticated;
grant execute on function demo.current_published_snapshot() to postgres, service_role;

-- PostgREST can call only exposed schemas. This wrapper does not read tables.
-- It delegates to the private definer function, which returns one sanitized document.
create or replace function public.rpc_v1_demo_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select demo.current_published_snapshot();
$$;

revoke all on function public.rpc_v1_demo_snapshot() from public;
grant execute on function public.rpc_v1_demo_snapshot() to anon, authenticated;

revoke all on schema demo from anon, authenticated;
grant usage on schema demo to anon, authenticated;
grant execute on function demo.current_published_snapshot() to anon, authenticated;

comment on function public.rpc_v1_demo_snapshot() is
  'Returns the current published Demo snapshot, or null when none is published.';

insert into demo.publications (version, schema_version, published_at, snapshot, is_current)
values (
  1,
  1,
  timestamptz '2026-10-03T02:23:37.687+00:00',
  $demo_snapshot${"accounts":[{"accountNumber":"APX-8821","canAddTrades":true,"category":"propFirm","id":"demo.account.evaluation","isActive":true,"mode":"evaluation","name":"Apex 50K Evaluation","ownerProfileID":"demo.explore.trader","propFirmRules":{"consistencyPercent":40,"dailyDrawdown":1200,"maxDrawdown":2500,"payoutDrawdownBehavior":"keep_trailing","profitTarget":3000,"winningDayThreshold":150,"winningDaysRequired":5},"showInAccountDropdowns":true,"size":{"amount":50000,"currencyCode":"USD"}},{"accountNumber":"APX-9014","canAddTrades":true,"category":"propFirm","id":"demo.account.funded","isActive":true,"mode":"funded","name":"Apex 50K Funded","ownerProfileID":"demo.explore.trader","propFirmRules":{"dailyDrawdown":1200,"maxDrawdown":2500,"payoutDrawdownBehavior":"keep_trailing"},"showInAccountDropdowns":true,"size":{"amount":50000,"currencyCode":"USD"}},{"accountNumber":"TV-44102","canAddTrades":true,"category":"personal","id":"demo.account.live","isActive":true,"mode":"live","name":"Tradovate Personal","ownerProfileID":"demo.explore.trader","showInAccountDropdowns":true,"size":{"amount":25000,"currencyCode":"USD"}}],"achievements":[{"accountID":"demo.account.funded","achievedAt":"2026-09-15T02:23:37.695Z","description":"Payout recorded on the Apex 50K Funded account.","firm":"Apex","id":"demo.achievement.payout","image":{"altText":"Payout","id":"https:\/\/images.unsplash.com\/photo-1611974789855-9c2a0a7236a3?w=1200&q=80","kind":"image"},"isFeatured":true,"isPublic":true,"kind":"prop_firm_payout","ownerProfileID":"demo.explore.trader","sortOrder":0,"tier":"gold","title":"Funded payout","value":{"amount":1850,"currencyCode":"USD"}}],"activity":[{"actorProfileID":"demo.profile.alex","body":"","createdAt":"2026-10-03T02:13:37.687Z","id":"demo.activity.like","isMention":false,"isRead":false,"isReply":false,"kind":"like","title":"like","tradeID":"demo-trade-2-0"},{"actorProfileID":"demo.profile.sarah","body":"","createdAt":"2026-10-03T01:23:37.687Z","id":"demo.activity.follow","isMention":false,"isRead":false,"isReply":false,"kind":"follow","title":"follow"},{"actorProfileID":"demo.profile.mike","body":"Clean process note.","createdAt":"2026-10-03T00:23:37.687Z","id":"demo.activity.comment","isMention":false,"isRead":true,"isReply":false,"kind":"comment","postID":"demo.post.note","title":"comment"},{"actorProfileID":"demo.profile.alex","body":"","createdAt":"2026-10-02T22:30:17.687Z","id":"demo.activity.room","isMention":true,"isRead":true,"isReply":false,"kind":"room_mention","messagePreview":"Check the MNQ recap","roomID":"demo.explore.trade-room","roomName":"TradeTraxs Traders","roomSlug":"tradetraxs-traders","sectionName":"General","title":"room_mention"},{"body":"Your monthly summary is ready","createdAt":"2026-10-02T02:23:37.687Z","id":"demo.activity.report","isMention":false,"isRead":true,"isReply":false,"kind":"trading_report","reportID":"monthly_last","title":"Monthly trading report"}],"channels":[{"allowMembersChat":true,"id":"demo.explore.trade-room-general","name":"general","position":0,"roomID":"demo.explore.trade-room"},{"allowMembersChat":true,"id":"demo.explore.trade-room-setups","name":"setups","position":1,"roomID":"demo.explore.trade-room"},{"allowMembersChat":true,"id":"demo.explore.trade-room-recap","name":"recap","position":2,"roomID":"demo.explore.trade-room"}],"checkIns":[{"checkInDate":"2026-09-30","createdAt":"2026-09-30T15:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-09-30","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-09-30T15:15:00.000Z"},{"checkInDate":"2026-09-27","createdAt":"2026-09-27T14:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-09-27","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-09-27T14:15:00.000Z"},{"checkInDate":"2026-09-24","createdAt":"2026-09-24T13:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-09-24","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-09-24T13:15:00.000Z"},{"checkInDate":"2026-09-21","createdAt":"2026-09-21T16:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-09-21","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-09-21T16:15:00.000Z"},{"checkInDate":"2026-09-18","createdAt":"2026-09-18T15:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-09-18","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-09-18T15:15:00.000Z"},{"checkInDate":"2026-09-15","createdAt":"2026-09-15T14:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-09-15","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-09-15T14:15:00.000Z"},{"checkInDate":"2026-09-12","createdAt":"2026-09-12T13:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-09-12","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-09-12T13:15:00.000Z"},{"checkInDate":"2026-09-09","createdAt":"2026-09-09T16:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-09-09","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-09-09T16:15:00.000Z"},{"checkInDate":"2026-09-06","createdAt":"2026-09-06T15:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-09-06","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-09-06T15:15:00.000Z"},{"checkInDate":"2026-09-03","createdAt":"2026-09-03T14:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-09-03","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-09-03T14:15:00.000Z"},{"checkInDate":"2026-08-31","createdAt":"2026-08-31T13:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-08-31","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-08-31T13:15:00.000Z"},{"checkInDate":"2026-08-28","createdAt":"2026-08-28T16:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-08-28","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-08-28T16:15:00.000Z"},{"checkInDate":"2026-08-25","createdAt":"2026-08-25T15:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-08-25","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-08-25T15:15:00.000Z"},{"checkInDate":"2026-08-22","createdAt":"2026-08-22T14:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-08-22","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-08-22T14:15:00.000Z"},{"checkInDate":"2026-08-19","createdAt":"2026-08-19T13:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-08-19","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-08-19T13:15:00.000Z"},{"checkInDate":"2026-08-16","createdAt":"2026-08-16T16:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-08-16","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-08-16T16:15:00.000Z"},{"checkInDate":"2026-08-13","createdAt":"2026-08-13T15:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-08-13","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-08-13T15:15:00.000Z"},{"checkInDate":"2026-08-10","createdAt":"2026-08-10T14:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-08-10","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-08-10T14:15:00.000Z"},{"checkInDate":"2026-08-07","createdAt":"2026-08-07T13:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-08-07","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-08-07T13:15:00.000Z"},{"checkInDate":"2026-08-04","createdAt":"2026-08-04T16:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-08-04","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-08-04T16:15:00.000Z"},{"checkInDate":"2026-08-01","createdAt":"2026-08-01T15:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-08-01","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-08-01T15:15:00.000Z"},{"checkInDate":"2026-07-29","createdAt":"2026-07-29T14:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-07-29","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-07-29T14:15:00.000Z"},{"checkInDate":"2026-07-26","createdAt":"2026-07-26T13:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-07-26","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-07-26T13:15:00.000Z"},{"checkInDate":"2026-07-23","createdAt":"2026-07-23T16:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-07-23","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-07-23T16:15:00.000Z"},{"checkInDate":"2026-07-20","createdAt":"2026-07-20T15:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-07-20","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-07-20T15:15:00.000Z"},{"checkInDate":"2026-07-17","createdAt":"2026-07-17T14:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-07-17","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-07-17T14:15:00.000Z"},{"checkInDate":"2026-07-14","createdAt":"2026-07-14T13:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-07-14","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-07-14T13:15:00.000Z"},{"checkInDate":"2026-07-11","createdAt":"2026-07-11T16:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-07-11","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-07-11T16:15:00.000Z"},{"checkInDate":"2026-07-08","createdAt":"2026-07-08T15:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-07-08","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-07-08T15:15:00.000Z"},{"checkInDate":"2026-07-05","createdAt":"2026-07-05T14:15:00.000Z","energyLevel":2,"focusLevel":2,"id":"demo.checkin.2026-07-05","morningRating":2,"notes":"Short sleep. Noted the impulse to size up after the first loss.","ownerProfileID":"demo.explore.trader","sleepHours":5.5,"sleepQuality":2,"stressLevel":4,"updatedAt":"2026-07-05T14:15:00.000Z"},{"checkInDate":"2026-07-02","createdAt":"2026-07-02T13:15:00.000Z","energyLevel":4,"focusLevel":5,"id":"demo.checkin.2026-07-02","morningRating":4,"notes":"Slept through the night and stuck to the plan.","ownerProfileID":"demo.explore.trader","sleepHours":7.5,"sleepQuality":4,"stressLevel":2,"updatedAt":"2026-07-02T13:15:00.000Z"}],"clips":[{"authorProfileID":"demo.explore.trader","caption":"NQ recap","createdAt":"2026-09-30T15:15:00.000Z","durationSeconds":10,"id":"demo.clip.open","linkedTradeID":"demo-trade-2-0","thumbnail":{"altText":"Clip","id":"https:\/\/images.unsplash.com\/photo-1611974789855-9c2a0a7236a3?w=1200&q=80","kind":"image"},"video":{"id":"https:\/\/test-videos.co.uk\/vids\/bigbuckbunny\/mp4\/h264\/360\/Big_Buck_Bunny_360_10s_1MB.mp4","kind":"video"},"visibility":"public"}],"conversations":[{"id":"demo.dm.sarah","isGroup":false,"isMuted":false,"isPinned":true,"lastMessageAt":"2026-10-03T02:08:37.695Z","lastMessagePreview":"Shared NQ","participantProfileIDs":["demo.explore.trader","demo.profile.sarah"],"peerUsername":"sarah","title":"Sarah Chen","unreadCount":1,"updatedAt":"2026-10-03T02:08:37.695Z"}],"host":{"avatar":{"altText":"TradeTraxs logo","id":"bundle:AppLogo","kind":"image"},"bio":"Official community host for TradeTraxs Traders.","createdAt":"2024-10-27T03:33:20.000Z","displayName":"TradeTraxs Community","id":"demo.explore.community.host","isCreator":true,"isPrivate":false,"traderType":"Futures","userID":"demo.explore.community.host","username":"tradetraxs_host","usernameChangeCount":0},"memberships":[{"joinedAt":"2026-06-05T02:23:37.687Z","notificationsEnabled":true,"profileID":"demo.explore.community.host","role":"owner","roomID":"demo.explore.trade-room"},{"joinedAt":"2026-06-06T02:23:37.687Z","notificationsEnabled":true,"profileID":"demo.profile.sarah","role":"admin","roomID":"demo.explore.trade-room"},{"joinedAt":"2026-06-07T02:23:37.687Z","notificationsEnabled":true,"profileID":"demo.profile.alex","role":"member","roomID":"demo.explore.trade-room"},{"joinedAt":"2026-06-07T09:56:57.687Z","notificationsEnabled":true,"profileID":"demo.profile.mike","role":"member","roomID":"demo.explore.trade-room"},{"joinedAt":"2026-09-26T02:23:37.687Z","notificationsEnabled":true,"profileID":"demo.explore.trader","role":"member","roomID":"demo.explore.trade-room"}],"messages":[{"attachments":[],"body":"That NQ is the one from your journal.","conversationID":"demo.dm.sarah","createdAt":"2026-10-03T01:53:37.696Z","id":"demo.dm.sarah.hello","isReadByViewer":true,"kind":"text","roomReactions":[],"senderProfileID":"demo.profile.sarah"},{"attachments":[],"conversationID":"demo.dm.sarah","createdAt":"2026-10-03T02:08:37.696Z","id":"demo.dm.sarah.trade","isReadByViewer":false,"kind":"tradeShare","roomReactions":[],"senderProfileID":"demo.profile.sarah","sharedContent":{"trade":{"_0":"demo-trade-2-0"}}}],"payouts":[{"accountID":"demo.account.funded","amount":{"amount":1850,"currencyCode":"USD"},"id":"demo-payout-1","note":"First funded payout","payoutDate":"2026-08-19T02:23:37.693Z"},{"accountID":"demo.account.funded","amount":{"amount":2400,"currencyCode":"USD"},"id":"demo-payout-2","note":"Consistency week","payoutDate":"2026-09-15T02:23:37.693Z"}],"peers":[{"bio":"Demo trader. Opening drive.","createdAt":"2024-01-01T00:00:00.000Z","displayName":"Alex Rivera","id":"demo.profile.alex","isCreator":false,"isPrivate":false,"primaryMarket":"NQ","startedTradingAt":"2024-01-01T00:00:00.000Z","traderType":"Futures","tradingStyle":"Opening drive","userID":"demo.profile.alex","username":"alex","usernameChangeCount":0},{"bio":"Demo trader. Liquidity sweep.","createdAt":"2024-01-01T00:00:00.000Z","displayName":"Sarah Chen","id":"demo.profile.sarah","isCreator":false,"isPrivate":false,"primaryMarket":"NQ","startedTradingAt":"2024-01-01T00:00:00.000Z","traderType":"Futures","tradingStyle":"Liquidity sweep","userID":"demo.profile.sarah","username":"sarah","usernameChangeCount":0},{"bio":"Demo trader. VWAP rejection.","createdAt":"2024-01-01T00:00:00.000Z","displayName":"Mike Alvarez","id":"demo.profile.mike","isCreator":false,"isPrivate":false,"primaryMarket":"NQ","startedTradingAt":"2024-01-01T00:00:00.000Z","traderType":"Futures","tradingStyle":"VWAP rejection","userID":"demo.profile.mike","username":"mike","usernameChangeCount":0}],"posts":[{"authorProfileID":"demo.explore.trader","body":"NQ long — logged on the NY plan.","createdAt":"2026-09-30T15:15:00.000Z","id":"demo.post.session","isPinned":true,"linkedTradeID":"demo-trade-2-0","media":[{"altText":"Session chart","id":"https:\/\/images.unsplash.com\/photo-1611974789855-9c2a0a7236a3?w=1200&q=80","kind":"image"}],"updatedAt":"2026-09-30T15:45:00.000Z","visibility":"public"},{"authorProfileID":"demo.explore.trader","body":"Process note: size stayed inside the plan after the first loss.","createdAt":"2026-10-02T02:23:37.694Z","id":"demo.post.note","isPinned":false,"media":[],"updatedAt":"2026-10-02T02:23:37.694Z","visibility":"public"}],"publishedAt":"2026-10-03T02:23:37.687Z","room":{"category":"day_trading","createdAt":"2026-06-05T02:23:37.687Z","description":"A community room for traders to share setups, discuss the markets, and review trades together.","discoveryTags":["futures","day-trading","journal"],"id":"demo.explore.trade-room","image":{"altText":"TradeTraxs logo","id":"bundle:AppLogo","kind":"image"},"isPrivate":false,"joinPolicy":"open","memberCount":1842,"membersCanMessage":true,"membersCanShareMedia":true,"membersCanShareTrades":true,"name":"TradeTraxs Traders","ownerProfileID":"demo.explore.community.host","roomKind":"community","rules":"Be respectful · No financial advice · Share process, not hype.","showsOnProfile":true,"slug":"tradetraxs-traders"},"roomMessages":[{"body":"Welcome to TradeTraxs Traders — share your plan before the open and recap after the close.","channelID":"demo.explore.trade-room-general","createdAt":"2026-09-30T02:23:37.687Z","id":"demo.explore.trade-room-welcome","isPinned":true,"media":[],"reactions":[],"roomID":"demo.explore.trade-room","senderProfileID":"demo.explore.community.host"},{"body":"NQ: watching prior day high and the 15m FVG into London. No chase without displacement.","channelID":"demo.explore.trade-room-setups","createdAt":"2026-10-03T00:23:37.687Z","id":"demo.explore.trade-room-nq-levels","isPinned":false,"media":[],"reactions":[],"roomID":"demo.explore.trade-room","senderProfileID":"demo.profile.sarah"},{"body":"Solid — post your screenshot when you're flat so we can review R-multiple.","channelID":"demo.explore.trade-room-setups","createdAt":"2026-10-03T00:30:17.687Z","id":"demo.explore.trade-room-reply","isPinned":false,"media":[],"parentMessageID":"demo.explore.trade-room-nq-levels","reactions":[],"roomID":"demo.explore.trade-room","senderProfileID":"demo.explore.community.host"},{"body":"Took one MNQ long off the sweep — stopped at BE after partial. Journaled in TradeTraxs.","channelID":"demo.explore.trade-room-recap","createdAt":"2026-10-03T01:23:37.687Z","id":"demo.explore.trade-room-viewer-recap","isPinned":false,"media":[],"reactions":[],"roomID":"demo.explore.trade-room","senderProfileID":"demo.explore.trader"},{"attachedTradeID":"demo-trade-2-0","body":"Shared a trade","channelID":"demo.explore.trade-room-recap","createdAt":"2026-10-03T01:53:37.687Z","id":"demo.explore.trade-room-trade-share","isPinned":false,"media":[],"reactions":[{"createdAt":"2026-10-03T01:55:17.687Z","id":"demo-explore-react-1","messageID":"demo.explore.trade-room-trade-share","reaction":"🔥","userID":"demo.explore.community.host"}],"roomID":"demo.explore.trade-room","senderProfileID":"demo.profile.sarah"},{"body":"Nice discipline on the BE management. See you in general for the NY open.","channelID":"demo.explore.trade-room-general","createdAt":"2026-10-03T02:08:37.687Z","id":"demo.explore.trade-room-close","isPinned":false,"media":[],"reactions":[],"roomID":"demo.explore.trade-room","senderProfileID":"demo.explore.community.host"}],"schemaVersion":1,"stories":[{"authorProfileID":"demo.profile.sarah","createdAt":"2026-10-03T02:08:37.694Z","expiresAt":"2026-10-04T02:23:37.694Z","id":"demo.story.demo.profile.sarah","media":{"altText":"Story","id":"https:\/\/images.unsplash.com\/photo-1611974789855-9c2a0a7236a3?w=1200&q=80","kind":"image"},"viewerHasSeen":false},{"authorProfileID":"demo.profile.alex","createdAt":"2026-10-03T01:53:37.694Z","expiresAt":"2026-10-04T02:23:37.694Z","id":"demo.story.demo.profile.alex","media":{"altText":"Story","id":"https:\/\/images.unsplash.com\/photo-1611974789855-9c2a0a7236a3?w=1200&q=80","kind":"image"},"viewerHasSeen":false},{"authorProfileID":"demo.explore.trader","createdAt":"2026-10-03T01:38:37.694Z","expiresAt":"2026-10-04T02:23:37.694Z","id":"demo.story.demo.explore.trader","media":{"altText":"Story","id":"https:\/\/images.unsplash.com\/photo-1611974789855-9c2a0a7236a3?w=1200&q=80","kind":"image"},"viewerHasSeen":true}],"trades":[{"accountID":"demo.account.evaluation","createdAt":"2026-09-30T15:15:00.000Z","entryAt":"2026-09-30T15:15:00.000Z","entryPrice":18420,"exitAt":"2026-09-30T15:45:00.000Z","exitPrice":18446,"id":"demo-trade-2-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-09-30T15:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-09-27T14:15:00.000Z","entryAt":"2026-09-27T14:15:00.000Z","entryPrice":5210,"exitAt":"2026-09-27T14:45:00.000Z","exitPrice":5220,"id":"demo-trade-5-0","imageDisplayMode":"fit","mode":"live","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":-95,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"short","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-09-27T14:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-09-24T13:15:00.000Z","entryAt":"2026-09-24T13:15:00.000Z","entryPrice":18400,"exitAt":"2026-09-24T13:45:00.000Z","exitPrice":18426,"id":"demo-trade-8-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-09-24T13:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-09-21T16:15:00.000Z","entryAt":"2026-09-21T16:15:00.000Z","entryPrice":18430,"exitAt":"2026-09-21T16:45:00.000Z","exitPrice":18410,"id":"demo-trade-11-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":20,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY PM","side":"short","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-09-21T16:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-09-18T15:15:00.000Z","entryAt":"2026-09-18T15:15:00.000Z","entryPrice":5220,"exitAt":"2026-09-18T15:45:00.000Z","exitPrice":5210,"id":"demo-trade-14-0","imageDisplayMode":"fit","mode":"live","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":-180,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-09-18T15:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-09-15T14:15:00.000Z","entryAt":"2026-09-15T14:15:00.000Z","entryPrice":18410,"exitAt":"2026-09-15T14:45:00.000Z","exitPrice":18410,"id":"demo-trade-17-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":0,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":0,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"short","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-09-15T14:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-09-12T13:15:00.000Z","entryAt":"2026-09-12T13:15:00.000Z","entryPrice":18440,"exitAt":"2026-09-12T13:45:00.000Z","exitPrice":18466,"id":"demo-trade-20-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-09-12T13:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-09-09T16:15:00.000Z","entryAt":"2026-09-09T16:15:00.000Z","entryPrice":5230,"exitAt":"2026-09-09T16:45:00.000Z","exitPrice":5210,"id":"demo-trade-23-0","imageDisplayMode":"fit","mode":"live","ownerProfileID":"demo.explore.trader","points":20,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY PM","side":"short","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-09-09T16:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-09-06T15:15:00.000Z","entryAt":"2026-09-06T15:15:00.000Z","entryPrice":18420,"exitAt":"2026-09-06T15:45:00.000Z","exitPrice":18410,"id":"demo-trade-26-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":-95,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-09-06T15:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-09-03T14:15:00.000Z","entryAt":"2026-09-03T14:15:00.000Z","entryPrice":18450,"exitAt":"2026-09-03T14:45:00.000Z","exitPrice":18430,"id":"demo-trade-29-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":20,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"short","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-09-03T14:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-08-31T13:15:00.000Z","entryAt":"2026-08-31T13:15:00.000Z","entryPrice":5200,"exitAt":"2026-08-31T13:45:00.000Z","exitPrice":5226,"id":"demo-trade-32-0","imageDisplayMode":"fit","mode":"live","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-08-31T13:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-08-28T16:15:00.000Z","entryAt":"2026-08-28T16:15:00.000Z","entryPrice":18430,"exitAt":"2026-08-28T16:45:00.000Z","exitPrice":18440,"id":"demo-trade-35-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":-180,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY PM","side":"short","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-08-28T16:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-08-25T15:15:00.000Z","entryAt":"2026-08-25T15:15:00.000Z","entryPrice":18460,"exitAt":"2026-08-25T15:45:00.000Z","exitPrice":18460,"id":"demo-trade-38-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":0,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":0,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-08-25T15:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-08-22T14:15:00.000Z","entryAt":"2026-08-22T14:15:00.000Z","entryPrice":5210,"exitAt":"2026-08-22T14:45:00.000Z","exitPrice":5190,"id":"demo-trade-41-0","imageDisplayMode":"fit","mode":"live","ownerProfileID":"demo.explore.trader","points":20,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"short","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-08-22T14:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-08-19T13:15:00.000Z","entryAt":"2026-08-19T13:15:00.000Z","entryPrice":18440,"exitAt":"2026-08-19T13:45:00.000Z","exitPrice":18466,"id":"demo-trade-44-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-08-19T13:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-08-16T16:15:00.000Z","entryAt":"2026-08-16T16:15:00.000Z","entryPrice":18470,"exitAt":"2026-08-16T16:45:00.000Z","exitPrice":18480,"id":"demo-trade-47-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":-95,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY PM","side":"short","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-08-16T16:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-08-13T15:15:00.000Z","entryAt":"2026-08-13T15:15:00.000Z","entryPrice":5220,"exitAt":"2026-08-13T15:45:00.000Z","exitPrice":5246,"id":"demo-trade-50-0","imageDisplayMode":"fit","mode":"live","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-08-13T15:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-08-10T14:15:00.000Z","entryAt":"2026-08-10T14:15:00.000Z","entryPrice":18450,"exitAt":"2026-08-10T14:45:00.000Z","exitPrice":18430,"id":"demo-trade-53-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":20,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"short","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-08-10T14:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-08-07T13:15:00.000Z","entryAt":"2026-08-07T13:15:00.000Z","entryPrice":18400,"exitAt":"2026-08-07T13:45:00.000Z","exitPrice":18390,"id":"demo-trade-56-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":-180,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-08-07T13:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-08-04T16:15:00.000Z","entryAt":"2026-08-04T16:15:00.000Z","entryPrice":5230,"exitAt":"2026-08-04T16:45:00.000Z","exitPrice":5230,"id":"demo-trade-59-0","imageDisplayMode":"fit","mode":"live","ownerProfileID":"demo.explore.trader","points":0,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":0,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY PM","side":"short","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-08-04T16:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-08-01T15:15:00.000Z","entryAt":"2026-08-01T15:15:00.000Z","entryPrice":18460,"exitAt":"2026-08-01T15:45:00.000Z","exitPrice":18486,"id":"demo-trade-62-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-08-01T15:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-07-29T14:15:00.000Z","entryAt":"2026-07-29T14:15:00.000Z","entryPrice":18410,"exitAt":"2026-07-29T14:45:00.000Z","exitPrice":18390,"id":"demo-trade-65-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":20,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"short","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-07-29T14:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-07-26T13:15:00.000Z","entryAt":"2026-07-26T13:15:00.000Z","entryPrice":5200,"exitAt":"2026-07-26T13:45:00.000Z","exitPrice":5190,"id":"demo-trade-68-0","imageDisplayMode":"fit","mode":"live","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":-95,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-07-26T13:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-07-23T16:15:00.000Z","entryAt":"2026-07-23T16:15:00.000Z","entryPrice":18470,"exitAt":"2026-07-23T16:45:00.000Z","exitPrice":18450,"id":"demo-trade-71-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":20,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY PM","side":"short","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-07-23T16:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-07-20T15:15:00.000Z","entryAt":"2026-07-20T15:15:00.000Z","entryPrice":18420,"exitAt":"2026-07-20T15:45:00.000Z","exitPrice":18446,"id":"demo-trade-74-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-07-20T15:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-07-17T14:15:00.000Z","entryAt":"2026-07-17T14:15:00.000Z","entryPrice":5210,"exitAt":"2026-07-17T14:45:00.000Z","exitPrice":5220,"id":"demo-trade-77-0","imageDisplayMode":"fit","mode":"live","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":-180,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"short","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-07-17T14:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-07-14T13:15:00.000Z","entryAt":"2026-07-14T13:15:00.000Z","entryPrice":18400,"exitAt":"2026-07-14T13:45:00.000Z","exitPrice":18400,"id":"demo-trade-80-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":0,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":0,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-07-14T13:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-07-11T16:15:00.000Z","entryAt":"2026-07-11T16:15:00.000Z","entryPrice":18430,"exitAt":"2026-07-11T16:45:00.000Z","exitPrice":18410,"id":"demo-trade-83-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":20,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY PM","side":"short","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-07-11T16:45:00.000Z","visibility":"public"},{"accountID":"demo.account.live","createdAt":"2026-07-08T15:15:00.000Z","entryAt":"2026-07-08T15:15:00.000Z","entryPrice":5220,"exitAt":"2026-07-08T15:45:00.000Z","exitPrice":5246,"id":"demo-trade-86-0","imageDisplayMode":"fit","mode":"live","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":1,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"ES"},"updatedAt":"2026-07-08T15:45:00.000Z","visibility":"public"},{"accountID":"demo.account.funded","createdAt":"2026-07-05T14:15:00.000Z","entryAt":"2026-07-05T14:15:00.000Z","entryPrice":18410,"exitAt":"2026-07-05T14:45:00.000Z","exitPrice":18420,"id":"demo-trade-89-0","imageDisplayMode":"fit","mode":"sim","ownerProfileID":"demo.explore.trader","points":10,"publicCaption":"Session recap","quantity":4,"realizedPnL":{"amount":-95,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"short","strategy":"Opening drive","symbol":{"ticker":"MNQ"},"updatedAt":"2026-07-05T14:45:00.000Z","visibility":"public"},{"accountID":"demo.account.evaluation","createdAt":"2026-07-02T13:15:00.000Z","entryAt":"2026-07-02T13:15:00.000Z","entryPrice":18440,"exitAt":"2026-07-02T13:45:00.000Z","exitPrice":18466,"id":"demo-trade-92-0","imageDisplayMode":"fit","mode":"sim","notePreview":"Waited for confirmation; sized to plan.","ownerProfileID":"demo.explore.trader","points":26,"publicCaption":"Session recap","quantity":2,"realizedPnL":{"amount":290,"currencyCode":"USD"},"riskReward":0.8,"sessionLabel":"NY","side":"long","strategy":"Opening drive","symbol":{"ticker":"NQ"},"updatedAt":"2026-07-02T13:45:00.000Z","visibility":"public"}],"vaultFolders":[{"createdAt":"2026-09-13T02:23:37.687Z","id":"demo.vault.reviews","name":"Setups to review","updatedAt":"2026-10-01T02:23:37.687Z"}],"vaultItems":[{"createdAt":"2026-09-30T15:15:00.000Z","folderIDs":["demo.vault.reviews"],"id":"demo.vault.trade.demo-trade-2-0","ref":{"contentID":"demo-trade-2-0","contentType":"trade"}},{"createdAt":"2026-09-27T14:15:00.000Z","folderIDs":["demo.vault.reviews"],"id":"demo.vault.trade.demo-trade-5-0","ref":{"contentID":"demo-trade-5-0","contentType":"trade"}},{"createdAt":"2026-09-24T13:15:00.000Z","folderIDs":["demo.vault.reviews"],"id":"demo.vault.trade.demo-trade-8-0","ref":{"contentID":"demo-trade-8-0","contentType":"trade"}},{"createdAt":"2026-09-15T02:23:37.691Z","folderIDs":[],"id":"demo.vault.achievement.demo.achievement.payout","ref":{"contentID":"demo.achievement.payout","contentType":"achievement"}}],"version":1,"viewer":{"avatar":{"altText":"TradeTraxs logo","id":"bundle:AppLogo","kind":"image"},"bio":"Explore Mode demo journal · futures & index day trading with TradeTraxs.","createdAt":"2025-02-19T21:20:00.000Z","displayName":"TradeTraxs Test","id":"demo.explore.trader","isCreator":false,"isPrivate":false,"primaryMarket":"NQ","startedTradingAt":"2024-10-03T02:23:37.687Z","traderType":"Futures","tradingStyle":"Session structure","userID":"demo.explore.trader","username":"tradetraxs","usernameChangeCount":0}}$demo_snapshot$::jsonb,
  true
);

insert into demo.profiles (id, role, payload)
select pub.snapshot->'viewer'->>'id', 'viewer', pub.snapshot->'viewer'
from demo.publications pub
where pub.version = 1
union all
select peer->>'id', 'peer', peer
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'peers') peer
where pub.version = 1
union all
select pub.snapshot->'host'->>'id', 'host', pub.snapshot->'host'
from demo.publications pub
where pub.version = 1;

insert into demo.accounts (id, owner_profile_id, payload)
select item->>'id', item->>'ownerProfileID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'accounts') item
where pub.version = 1;

insert into demo.trades (id, account_id, owner_profile_id, payload)
select item->>'id', item->>'accountID', item->>'ownerProfileID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'trades') item
where pub.version = 1;

insert into demo.check_ins (id, owner_profile_id, payload)
select item->>'id', item->>'ownerProfileID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'checkIns') item
where pub.version = 1;

insert into demo.payouts (id, account_id, payload)
select item->>'id', item->>'accountID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'payouts') item
where pub.version = 1;

insert into demo.posts (id, author_profile_id, linked_trade_id, payload)
select item->>'id', item->>'authorProfileID', item->>'linkedTradeID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'posts') item
where pub.version = 1;

insert into demo.clips (id, author_profile_id, linked_trade_id, payload)
select item->>'id', item->>'authorProfileID', item->>'linkedTradeID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'clips') item
where pub.version = 1;

insert into demo.stories (id, author_profile_id, payload)
select item->>'id', item->>'authorProfileID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'stories') item
where pub.version = 1;

insert into demo.achievements (id, owner_profile_id, account_id, payload)
select item->>'id', item->>'ownerProfileID', item->>'accountID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'achievements') item
where pub.version = 1;

insert into demo.activity (id, actor_profile_id, trade_id, payload)
select item->>'id', item->>'actorProfileID', item->>'tradeID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'activity') item
where pub.version = 1;

insert into demo.conversations (id, payload)
select item->>'id', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'conversations') item
where pub.version = 1;

insert into demo.messages (id, conversation_id, sender_profile_id, payload)
select item->>'id', item->>'conversationID', item->>'senderProfileID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'messages') item
where pub.version = 1;

insert into demo.rooms (id, payload)
select pub.snapshot->'room'->>'id', pub.snapshot->'room'
from demo.publications pub
where pub.version = 1;

insert into demo.room_channels (id, room_id, payload)
select item->>'id', item->>'roomID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'channels') item
where pub.version = 1;

insert into demo.room_memberships (room_id, profile_id, role, payload)
select item->>'roomID', item->>'profileID', item->>'role', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'memberships') item
where pub.version = 1;

insert into demo.room_messages (id, room_id, channel_id, sender_profile_id, payload)
select item->>'id', item->>'roomID', item->>'channelID', item->>'senderProfileID', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'roomMessages') item
where pub.version = 1;

insert into demo.vault_folders (id, payload)
select item->>'id', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'vaultFolders') item
where pub.version = 1;

insert into demo.vault_items (id, payload)
select item->>'id', item
from demo.publications pub
cross join lateral jsonb_array_elements(pub.snapshot->'vaultItems') item
where pub.version = 1;

alter table demo.accounts
  add constraint demo_accounts_owner_fkey
  foreign key (owner_profile_id) references demo.profiles (id);

alter table demo.trades
  add constraint demo_trades_account_fkey
  foreign key (account_id) references demo.accounts (id),
  add constraint demo_trades_owner_fkey
  foreign key (owner_profile_id) references demo.profiles (id);

alter table demo.check_ins
  add constraint demo_check_ins_owner_fkey
  foreign key (owner_profile_id) references demo.profiles (id);

alter table demo.payouts
  add constraint demo_payouts_account_fkey
  foreign key (account_id) references demo.accounts (id);

alter table demo.posts
  add constraint demo_posts_author_fkey
  foreign key (author_profile_id) references demo.profiles (id),
  add constraint demo_posts_trade_fkey
  foreign key (linked_trade_id) references demo.trades (id);

alter table demo.clips
  add constraint demo_clips_author_fkey
  foreign key (author_profile_id) references demo.profiles (id),
  add constraint demo_clips_trade_fkey
  foreign key (linked_trade_id) references demo.trades (id);

alter table demo.stories
  add constraint demo_stories_author_fkey
  foreign key (author_profile_id) references demo.profiles (id);

alter table demo.achievements
  add constraint demo_achievements_owner_fkey
  foreign key (owner_profile_id) references demo.profiles (id),
  add constraint demo_achievements_account_fkey
  foreign key (account_id) references demo.accounts (id);

alter table demo.activity
  add constraint demo_activity_actor_fkey
  foreign key (actor_profile_id) references demo.profiles (id),
  add constraint demo_activity_trade_fkey
  foreign key (trade_id) references demo.trades (id);

alter table demo.messages
  add constraint demo_messages_conversation_fkey
  foreign key (conversation_id) references demo.conversations (id),
  add constraint demo_messages_sender_fkey
  foreign key (sender_profile_id) references demo.profiles (id);

alter table demo.room_channels
  add constraint demo_room_channels_room_fkey
  foreign key (room_id) references demo.rooms (id);

alter table demo.room_memberships
  add constraint demo_room_memberships_room_fkey
  foreign key (room_id) references demo.rooms (id),
  add constraint demo_room_memberships_profile_fkey
  foreign key (profile_id) references demo.profiles (id);

alter table demo.room_messages
  add constraint demo_room_messages_room_fkey
  foreign key (room_id) references demo.rooms (id),
  add constraint demo_room_messages_channel_fkey
  foreign key (channel_id) references demo.room_channels (id),
  add constraint demo_room_messages_sender_fkey
  foreign key (sender_profile_id) references demo.profiles (id);
