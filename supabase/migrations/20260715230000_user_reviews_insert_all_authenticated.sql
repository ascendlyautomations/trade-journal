-- Allow any authenticated user to submit a review (public launch).
-- Previously restricted to is_beta_tester via user_reviews_insert_beta.

drop policy if exists "user_reviews_insert_beta" on public.user_reviews;
drop policy if exists "user_reviews_insert_own" on public.user_reviews;

create policy "user_reviews_insert_own"
  on public.user_reviews
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and rating between 1 and 5
    and char_length(trim(review)) > 0
    and status = 'pending'
    and featured = false
  );

comment on table public.user_reviews is
  'User product reviews; any authenticated user may insert their own pending review.';
