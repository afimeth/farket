-- Bulgu (backend, kritik → düzeltildi): swap_photo_positions() RPC'si, iki fotoğrafın
-- position'ını tek transaction içinde takas ediyor. Kısıt DEFERRABLE INITIALLY DEFERRED
-- olduğu için ara adımda geçici çakışma commit'e kadar kontrol edilmiyor (bkz.
-- 20260820010000_swap_photo_positions_rpc.sql).

BEGIN;
SELECT plan(5);

insert into public.cities (id, name) overriding system value values (900101, 'Test Şehir Swap');

SELECT tests.create_supabase_user('55555555-0000-0000-0000-000000000000', 'e@test.local');
SELECT tests.create_supabase_user('66666666-0000-0000-0000-000000000000', 'f@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('55555555-0000-0000-0000-000000000000', 'E', '1994-01-01', 'male', 900101, 'published'),
  ('66666666-0000-0000-0000-000000000000', 'F', '1994-01-01', 'male', 900101, 'published');

insert into public.photos (id, profile_id, position, storage_path_thumb, storage_path_full, moderation_status)
values
  ('aaaaaaaa-0000-0000-0000-000000000010', '55555555-0000-0000-0000-000000000000', 1,
   '55555555-0000-0000-0000-000000000000/a1_thumb.webp', '55555555-0000-0000-0000-000000000000/a1_full.webp', 'approved'),
  ('aaaaaaaa-0000-0000-0000-000000000011', '55555555-0000-0000-0000-000000000000', 2,
   '55555555-0000-0000-0000-000000000000/a2_thumb.webp', '55555555-0000-0000-0000-000000000000/a2_full.webp', 'approved');

SELECT tests.authenticate_as('55555555-0000-0000-0000-000000000000');

-- Eski (kısıt DEFERRABLE olmadan önceki / RPC'siz) iki-adımlı UPDATE yaklaşımı burada
-- taklit ediliyor: aynı transaction, aynı statement sırası — DEFERRED kısıt sayesinde artık
-- patlamıyor.
SELECT lives_ok(
  $$ select public.swap_photo_positions(
       'aaaaaaaa-0000-0000-0000-000000000010'::uuid,
       'aaaaaaaa-0000-0000-0000-000000000011'::uuid) $$,
  'İki fotoğrafın position''ı unique kısıta çarpmadan takas edilebilir'
);

SELECT is(
  (select position from public.photos where id = 'aaaaaaaa-0000-0000-0000-000000000010'),
  2,
  'İlk fotoğraf artık position 2''de'
);

SELECT is(
  (select position from public.photos where id = 'aaaaaaaa-0000-0000-0000-000000000011'),
  1,
  'İkinci fotoğraf artık position 1''de'
);

SELECT tests.authenticate_as('66666666-0000-0000-0000-000000000000');

SELECT throws_ok(
  $$ select public.swap_photo_positions(
       'aaaaaaaa-0000-0000-0000-000000000010'::uuid,
       'aaaaaaaa-0000-0000-0000-000000000011'::uuid) $$,
  'Fotoğraf bulunamadı',
  'Başkasının fotoğraflarını takas edemez'
);

SELECT tests.clear_authentication();

SELECT throws_ok(
  $$ select public.swap_photo_positions(
       'aaaaaaaa-0000-0000-0000-000000000010'::uuid,
       'aaaaaaaa-0000-0000-0000-000000000011'::uuid) $$,
  'Oturum açılmamış',
  'Oturum yoksa çağrılamaz'
);

SELECT * FROM finish();
ROLLBACK;
