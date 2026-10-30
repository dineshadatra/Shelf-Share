begin;

alter function public.save_book_listing(uuid,jsonb,jsonb,jsonb,jsonb,text)
  rename to save_book_listing_unchecked_legacy;
revoke all on function public.save_book_listing_unchecked_legacy(uuid,jsonb,jsonb,jsonb,jsonb,text)
  from public,anon,authenticated;

create function public.save_book_listing(
  p_book_copy_id uuid,
  p_title jsonb,
  p_copy jsonb,
  p_pricing jsonb,
  p_listing_details jsonb,
  p_declaration_type text,
  p_declaration_accepted boolean
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_declaration_accepted is distinct from true then
    raise exception 'The lawful ownership/rental-authority declaration must be affirmatively accepted';
  end if;
  return public.save_book_listing_unchecked_legacy(
    p_book_copy_id,p_title,p_copy,p_pricing,p_listing_details,p_declaration_type
  );
end;
$$;
revoke all on function public.save_book_listing(uuid,jsonb,jsonb,jsonb,jsonb,text,boolean)
  from public,anon;
grant execute on function public.save_book_listing(uuid,jsonb,jsonb,jsonb,jsonb,text,boolean)
  to authenticated;

commit;
