-- Brifing v3, bölüm 9 adım 2 (set_city): güvenlik ve kural testleri.

BEGIN;
SELECT plan(7);

insert into public.cities (id, name, is_active) overriding system value
values (900001, 'Test Şehir A', true), (900002, 'Test Şehir B', true), (900003, 'Test Pasif Şehir', false);
insert into public.districts (id, city_id, name) overriding system value
values (900001, 900001, 'Test İlçe');

SELECT tests.create_supabase_user('11111111-0000-0000-0000-000000000000', 'l@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, district_id, status)
values ('11111111-0000-0000-0000-000000000000', 'L', '1995-01-01', 'female', 900001, 900001, 'published');

SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');

-- ---------------------------------------------------------------------
-- 1) İlk şehir değişimi: Test Şehir A → Test Şehir B.
-- ---------------------------------------------------------------------
SELECT is(
  public.set_city(900002) ->> 'changed',
  'true',
  'İlk şehir değişimi kabul edilir'
);

SELECT is(
  (select city_id from public.profiles where id = '11111111-0000-0000-0000-000000000000'),
  900002,
  'profiles.city_id güncellendi'
);

SELECT is(
  (select district_id from public.profiles where id = '11111111-0000-0000-0000-000000000000'),
  null::int,
  'Şehir değişince eski district_id sıfırlanır'
);

-- ---------------------------------------------------------------------
-- 2) Aynı şehri tekrar seçmek no-op'tur, kilide takılmaz.
-- ---------------------------------------------------------------------
SELECT is(
  public.set_city(900002) ->> 'changed',
  'false',
  'Zaten bulunulan şehir tekrar seçilirse değişiklik sayılmaz (no-op)'
);

-- ---------------------------------------------------------------------
-- 3) 24 saat dolmadan farklı bir şehre geçmek reddedilir.
-- ---------------------------------------------------------------------
SELECT throws_matching(
  $$ select public.set_city(900001) $$,
  'Şehir değişikliği için 24 saat beklemelisin',
  '24 saat dolmadan ikinci bir şehir değişimi reddedilir'
);

-- ---------------------------------------------------------------------
-- 4) Geçersiz / pasif / var olmayan şehir.
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ select public.set_city(900003) $$,
  'Geçersiz şehir',
  'Pasif (is_active=false) bir şehir seçilemez'
);

SELECT throws_ok(
  $$ select public.set_city(999) $$,
  'Geçersiz şehir',
  'Var olmayan bir şehir seçilemez'
);

SELECT * FROM finish();
ROLLBACK;
