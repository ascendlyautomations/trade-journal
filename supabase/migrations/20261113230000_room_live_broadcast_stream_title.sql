-- Custom stream title for Trade Room live broadcasts (required for new sessions at app layer).

alter table public.room_live_broadcasts
  add column if not exists stream_title text;

comment on column public.room_live_broadcasts.stream_title is
  'Host-defined title shown in live UI and push copy (max 100 chars, validated in BFF).';

alter table public.room_live_broadcasts
  drop constraint if exists room_live_broadcasts_stream_title_len;

alter table public.room_live_broadcasts
  add constraint room_live_broadcasts_stream_title_len
  check (
    stream_title is null
    or (
      char_length(trim(stream_title)) >= 1
      and char_length(trim(stream_title)) <= 100
    )
  );

notify pgrst, 'reload schema';
