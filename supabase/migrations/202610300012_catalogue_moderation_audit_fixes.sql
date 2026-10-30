begin;

-- Previously approved copy photos remain valid evidence when a paused/rejected listing is
-- edited and resubmitted. New listings still require two owner-uploaded pending photos.
create or replace function public.submit_book_listing(p_book_copy_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists(
    select 1 from public.user_verifications v join public.profiles p on p.id=v.user_id
    where v.user_id=v_user and v.status='verified' and v.age_eligible is true and p.account_status='active'
  ) then raise exception 'Active identity verification is required'; end if;
  if not exists(select 1 from public.book_copies where id=p_book_copy_id and owner_id=v_user and listing_status in ('draft','rejected')) then
    raise exception 'Draft or rejected listing not found'; end if;
  if (select count(*) from public.book_images where book_copy_id=p_book_copy_id and moderation_status in ('pending_review','approved')) < 2 then
    raise exception 'At least two actual photographs of this physical copy are required'; end if;
  if not exists(select 1 from public.book_ownership_declarations where book_copy_id=p_book_copy_id and owner_id=v_user and withdrawn_at is null) then
    raise exception 'Ownership/rental-authority declaration is required'; end if;
  if not exists(select 1 from public.book_pricing where book_copy_id=p_book_copy_id and effective_until is null
    and (coalesce(rental_3d_paise,0)+coalesce(rental_7d_paise,0)+coalesce(rental_15d_paise,0)+coalesce(rental_30d_paise,0)+coalesce(custom_daily_paise,0))>0) then
    raise exception 'A valid rental price is required'; end if;
  update public.book_copies set listing_status='pending_review',is_available_for_rent=false where id=p_book_copy_id;
  insert into public.book_listing_moderation_events(book_copy_id,actor_user_id,action,from_status,to_status)
    values(p_book_copy_id,v_user,'submitted','draft','pending_review');
end;
$$;
revoke all on function public.submit_book_listing(uuid) from public,anon;
grant execute on function public.submit_book_listing(uuid) to authenticated;

create table public.book_listing_evidence_access_audit (
  id bigint generated always as identity primary key,
  book_copy_id uuid not null references public.book_copies(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  purpose text not null check(length(btrim(purpose)) between 5 and 500),
  accessed_at timestamptz not null default now()
);
create index book_listing_evidence_access_audit_copy_time_idx
  on public.book_listing_evidence_access_audit(book_copy_id,accessed_at desc);
alter table public.book_listing_evidence_access_audit enable row level security;
revoke all on public.book_listing_evidence_access_audit from anon,authenticated;

-- Audit and declaration records are append-only, including against accidental service writes.
create or replace function private.reject_append_only_mutation()
returns trigger language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'This record is append-only';
end;
$$;
drop trigger if exists book_ownership_declarations_append_only on public.book_ownership_declarations;
create trigger book_ownership_declarations_append_only
before update or delete on public.book_ownership_declarations
for each row execute function private.reject_append_only_mutation();
drop trigger if exists book_listing_moderation_events_append_only on public.book_listing_moderation_events;
create trigger book_listing_moderation_events_append_only
before update or delete on public.book_listing_moderation_events
for each row execute function private.reject_append_only_mutation();
drop trigger if exists book_listing_image_access_audit_append_only on public.book_listing_image_access_audit;
create trigger book_listing_image_access_audit_append_only
before update or delete on public.book_listing_image_access_audit
for each row execute function private.reject_append_only_mutation();
drop trigger if exists book_listing_evidence_access_audit_append_only on public.book_listing_evidence_access_audit;
create trigger book_listing_evidence_access_audit_append_only
before update or delete on public.book_listing_evidence_access_audit
for each row execute function private.reject_append_only_mutation();

commit;
