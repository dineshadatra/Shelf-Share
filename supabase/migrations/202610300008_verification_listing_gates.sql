begin;

-- Close the legacy update-policy gap: owners must remain active, verified and age eligible
-- for any direct listing edits. Column grants still limit which fields a member can change.
drop policy if exists book_copies_owner_insert on public.book_copies;
create policy book_copies_owner_insert on public.book_copies
for insert to authenticated
with check (
  owner_id = auth.uid()
  and listing_status = 'draft'
  and not is_available_for_rent
  and exists (
    select 1 from public.user_verifications v
    where v.user_id = auth.uid()
      and v.status = 'verified'
      and v.age_eligible is true
  )
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.account_status = 'active'
  )
);

drop policy if exists book_copies_owner_update on public.book_copies;
create policy book_copies_owner_update on public.book_copies
for update to authenticated
using (
  owner_id = auth.uid()
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.account_status = 'active'
  )
  and exists (
    select 1 from public.user_verifications v
    where v.user_id = auth.uid()
      and v.status = 'verified'
      and v.age_eligible is true
  )
)
with check (
  owner_id = auth.uid()
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.account_status = 'active'
  )
  and exists (
    select 1 from public.user_verifications v
    where v.user_id = auth.uid()
      and v.status = 'verified'
      and v.age_eligible is true
  )
);

-- Automatically pause every owned copy when manual verification is revoked, expires,
-- or moves into a resubmission/pending state. A service-side approval does not auto-publish
-- paused copies: listing moderation/reactivation remains a separate action.
create or replace function private.pause_owner_listings_after_verification_loss()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'verified' and new.status <> 'verified' then
    update public.book_copies
      set listing_status = 'paused',
          is_available_for_rent = false
      where owner_id = new.user_id
        and (listing_status <> 'paused' or is_available_for_rent = true);
  end if;
  return new;
end;
$$;

drop trigger if exists pause_listings_on_verification_loss on public.user_verifications;
create trigger pause_listings_on_verification_loss
after update of status on public.user_verifications
for each row
execute function private.pause_owner_listings_after_verification_loss();

-- Defense in depth if an administrator suspends/restricts a profile independently
-- of the identity-verification workflow.
create or replace function private.pause_owner_listings_after_account_restriction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.account_status = 'active' and new.account_status <> 'active' then
    update public.book_copies
      set listing_status = 'paused',
          is_available_for_rent = false
      where owner_id = new.id
        and (listing_status <> 'paused' or is_available_for_rent = true);
  end if;
  return new;
end;
$$;

drop trigger if exists pause_listings_on_account_restriction on public.profiles;
create trigger pause_listings_on_account_restriction
after update of account_status on public.profiles
for each row
execute function private.pause_owner_listings_after_account_restriction();

commit;
