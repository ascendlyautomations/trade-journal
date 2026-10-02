alter table public.stories
  add column if not exists text_overlays jsonb;

comment on column public.stories.text_overlays is
  'Video story text overlays in composer-canvas normalized coordinates. Photo stories burn text into the image and leave this null.';
