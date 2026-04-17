-- Cast audience_size to integer when column is still text-like (nullable).
do $$
begin
  if exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'affiliate_applications'
      and c.column_name = 'audience_size'
      and c.data_type in ('text', 'character varying')
  ) then
    alter table public.affiliate_applications
      alter column audience_size type integer using (
        case
          when nullif(trim(audience_size::text), '') is null then null
          else nullif(regexp_replace(trim(audience_size::text), '[^0-9]', '', 'g'), '')::integer
        end
      );
  end if;
end $$;
