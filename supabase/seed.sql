-- ShelfShare non-financial demonstration seed data only.
-- No users, fake payments, fake reviews, ledger entries, deposits, payouts or transactions.
-- Safe to re-run.
insert into public.cities (code, name, state_name, country_code, timezone, is_active)
values
  ('HYD', 'Hyderabad', 'Telangana', 'IN', 'Asia/Kolkata', true),
  ('BLR', 'Bengaluru', 'Karnataka', 'IN', 'Asia/Kolkata', true)
on conflict (code) do update
set name = excluded.name, state_name = excluded.state_name, timezone = excluded.timezone;

insert into public.categories (slug, name, description, is_active)
values
  ('fiction', 'Fiction', 'Fiction and literary works', true),
  ('non-fiction', 'Non-fiction', 'Non-fiction and general knowledge', true),
  ('business', 'Business', 'Business, management and entrepreneurship', true),
  ('technology', 'Technology', 'Computing, engineering and technology', true),
  ('self-help', 'Self-help', 'Personal development and wellbeing', true),
  ('academic', 'Academic', 'Academic and educational books', true),
  ('children', 'Children', 'Children and young readers', true)
on conflict (slug) do update
set name = excluded.name, description = excluded.description, is_active = excluded.is_active;
