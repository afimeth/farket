-- Sonraki Adımlar Görev 4: storage.objects RLS politikaları
-- (bucket 'profile-photos'). insert/update = yalnızca kendi klasörü
-- (auth.uid()); select = sahibi HER ZAMAN, başkası yalnızca discover_profiles
-- ile birebir aynı görünürlük kuralları altında. (DELETE ayrı test
-- edilmiyor — storage.protect_delete trigger'ı herkes için engelliyor.)

BEGIN;
SELECT plan(9);

-- ---------------------------------------------------------------------
-- Sabit test kimlikleri
--   Şehir 1 = İstanbul, Şehir 2 = Ankara
--   A = ...1 : fotoğraf sahibi, İstanbul, published
--   B = ...2 : A ile aynı şehir, ilişkisiz viewer
--   C = ...3 : A'yı engellemiş
--   D = ...4 : Ankara'da (farklı şehir)
-- ---------------------------------------------------------------------
insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir A'), (900002, 'Test Şehir B');

SELECT tests.create_supabase_user('11111111-0000-0000-0000-000000000000', 'a@test.local');
SELECT tests.create_supabase_user('22222222-0000-0000-0000-000000000000', 'b@test.local');
SELECT tests.create_supabase_user('33333333-0000-0000-0000-000000000000', 'c@test.local');
SELECT tests.create_supabase_user('44444444-0000-0000-0000-000000000000', 'd@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('11111111-0000-0000-0000-000000000000', 'A', '1994-01-01', 'male',   900001, 'published'),
  ('22222222-0000-0000-0000-000000000000', 'B', '1994-01-01', 'male',   900001, 'published'),
  ('33333333-0000-0000-0000-000000000000', 'C', '1994-01-01', 'male',   900001, 'published'),
  ('44444444-0000-0000-0000-000000000000', 'D', '1994-01-01', 'male',   900002, 'published');

insert into public.blocks (blocker_id, blocked_id)
values ('33333333-0000-0000-0000-000000000000', '11111111-0000-0000-0000-000000000000');

insert into public.photos (profile_id, position, storage_path_thumb, storage_path_full, moderation_status)
values (
  '11111111-0000-0000-0000-000000000000', 1,
  '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp',
  '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_full.webp',
  'approved'
);

-- ---------------------------------------------------------------------
-- INSERT: yalnızca kendi klasörüne, ada uyan biçimde.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');

SELECT lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('profile-photos', '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp') $$,
  'Kendi klasörüne, geçerli ad biçimiyle nesne ekleyebilir'
);

SELECT throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('profile-photos', '22222222-0000-0000-0000-000000000000/cccccccc-0000-0000-0000-000000000003_thumb.webp') $$,
  'new row violates row-level security policy for table "objects"',
  'Başkasının klasörüne nesne ekleyemez'
);

SELECT throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('profile-photos', '11111111-0000-0000-0000-000000000000/gecersiz-ad.webp') $$,
  'new row violates row-level security policy for table "objects"',
  'Ad biçimine uymayan (UUID_thumb|full.ext olmayan) nesne eklenemez'
);

-- ---------------------------------------------------------------------
-- SELECT: sahibi her zaman görebilir.
-- ---------------------------------------------------------------------
SELECT is(
  (select count(*)::int from storage.objects
   where name = '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp'),
  1,
  'Sahibi kendi fotoğrafını görebilir'
);

-- ---------------------------------------------------------------------
-- SELECT: aynı şehir, engelsiz, gizli değil -> görebilir.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');

SELECT is(
  (select count(*)::int from storage.objects
   where name = '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp'),
  1,
  'Aynı şehirdeki, engelsiz bir kullanıcı onaylı fotoğrafı görebilir'
);

-- ---------------------------------------------------------------------
-- SELECT: karşılıklı engelli -> görünmez.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');

SELECT is(
  (select count(*)::int from storage.objects
   where name = '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp'),
  0,
  'Engellenmiş kullanıcı fotoğrafı göremez'
);

-- ---------------------------------------------------------------------
-- SELECT: farklı şehir -> görünmez.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('44444444-0000-0000-0000-000000000000');

SELECT is(
  (select count(*)::int from storage.objects
   where name = '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp'),
  0,
  'Farklı şehirdeki kullanıcı fotoğrafı göremez'
);

-- ---------------------------------------------------------------------
-- UPDATE: yalnızca sahibi kendi klasöründeki nesneyi güncelleyebilir.
-- (DELETE, `storage.protect_delete` trigger'ıyla herkese kapalı — bkz.
-- migration'daki not; RLS-seviyeli delete testi bu yüzden anlamsız.)
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');

update storage.objects
set metadata = '{"hacked": true}'::jsonb
where bucket_id = 'profile-photos'
  and name = '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp';

SELECT is(
  (select metadata from storage.objects
   where name = '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp'),
  null::jsonb,
  'Başkası bir nesneyi güncelleyemez (RLS, metadata değişmedi)'
);

SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');

SELECT results_eq(
  $$ update storage.objects
     set metadata = '{"processed": true}'::jsonb
     where bucket_id = 'profile-photos'
       and name = '11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp'
     returning name $$,
  $$ values ('11111111-0000-0000-0000-000000000000/aaaaaaaa-0000-0000-0000-000000000001_thumb.webp'::text) $$,
  'Sahibi kendi nesnesini güncelleyebilir'
);

SELECT * FROM finish();
ROLLBACK;
