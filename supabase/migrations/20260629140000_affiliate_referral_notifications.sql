-- In-app affiliate referral notifications (one per referred user; one commission alert per referred user).

create unique index if not exists notifications_affiliate_referral_unique_idx
  on public.notifications (user_id, sender_id)
  where type = 'affiliate_referral';

create unique index if not exists notifications_affiliate_commission_unique_idx
  on public.notifications (user_id, sender_id)
  where type = 'affiliate_commission_earned';
