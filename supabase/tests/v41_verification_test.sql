-- v4.1 sonraki fazlar, Faz 4: doğrulama akışı (request_verification +
-- verification-selfies bucket). Onay/red v1'de ELLE yapılıyor (Studio) —
-- burada onun simülasyonu da (postgres olarak doğrudan update) test
-- ediliyor, get_quiz_allowance ile tam entegrasyon dahil.

BEGIN;
SELECT plan(14);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('44400000-0000-0000-0000-000000000000', 'u1@test.local');
SELECT tests.create_supabase_user('44400000-0000-0000-0000-000000000001', 'u2@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('44400000-0000-0000-0000-000000000000', 'U1', '1994-01-01', 'male', 900001, 'published'),
  ('44400000-0000-0000-0000-000000000001', 'U2', '1994-01-01', 'male', 900001, 'published');

-- ---------------------------------------------------------------------
-- Storage: yalnızca kendi klasörüne selfie yükleyebilir/görebilir.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('44400000-0000-0000-0000-000000000000');

SELECT lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('verification-selfies', '44400000-0000-0000-0000-000000000000/selfie.webp') $$,
  'Kendi klasörüne selfie yükleyebilir'
);

SELECT throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     values ('verification-selfies', '44400000-0000-0000-0000-000000000001/selfie.webp') $$,
  'new row violates row-level security policy for table "objects"',
  'Başkasının klasörüne selfie yükleyemez'
);

SELECT is(
  (select count(*)::int from storage.objects
     where bucket_id = 'verification-selfies' and name = '44400000-0000-0000-0000-000000000000/selfie.webp'),
  1,
  'Kendi selfie''sini görebilir'
);
SELECT tests.clear_authentication();

SELECT tests.authenticate_as('44400000-0000-0000-0000-000000000001');
SELECT is(
  (select count(*)::int from storage.objects
     where bucket_id = 'verification-selfies' and name = '44400000-0000-0000-0000-000000000000/selfie.webp'),
  0,
  'Başkası U1''in selfie''sini GÖREMEZ (kendi doğrulaması dahi olsa çapraz erişim yok)'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- request_verification
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('44400000-0000-0000-0000-000000000000');

SELECT is(
  public.get_my_verification_status(),
  'none',
  'get_my_verification_status: başvuru öncesi ''none'''
);

SELECT lives_ok(
  $$ select public.request_verification('44400000-0000-0000-0000-000000000000/selfie.webp') $$,
  'Geçerli bir doğrulama başvurusu yapılabilir'
);

SELECT is(
  public.get_my_verification_status(),
  'pending',
  'get_my_verification_status: başvuru sonrası ''pending'''
);

SELECT throws_ok(
  $$ select public.request_verification('44400000-0000-0000-0000-000000000000/selfie2.webp') $$,
  'Zaten bekleyen bir doğrulama başvurun var',
  'Bekleyen başvuru varken ikinci kez başvurulamaz'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- Elle onay simülasyonu (Studio'nun yapacağı işlem, postgres olarak).
-- ---------------------------------------------------------------------
update public.verification_requests
  set status = 'approved', reviewed_at = now()
  where profile_id = '44400000-0000-0000-0000-000000000000';
update public.profiles set verified_at = now()
  where id = '44400000-0000-0000-0000-000000000000';

SELECT tests.authenticate_as('44400000-0000-0000-0000-000000000000');

SELECT is(
  public.get_my_verification_status(),
  'verified',
  'get_my_verification_status: onay sonrası ''verified'''
);

SELECT throws_ok(
  $$ select public.request_verification('44400000-0000-0000-0000-000000000000/selfie3.webp') $$,
  'Zaten doğrulanmışsın',
  'Doğrulanmış kullanıcı tekrar başvuramaz'
);

-- Tam entegrasyon: get_quiz_allowance artık verified_at bonusunu yansıtıyor
-- (taban 3 + verified +1 + bekleyen mesaj isteği yok +1 = 5).
SELECT is(
  public.get_quiz_allowance('44400000-0000-0000-0000-000000000000'),
  5,
  'Onay sonrası get_quiz_allowance verified_at bonusunu yansıtıyor (henüz quiz_allowance saklanmadığı için canlı hesaplanıyor)'
);
SELECT tests.clear_authentication();

SELECT tests.authenticate_as('44400000-0000-0000-0000-000000000001');
SELECT throws_ok(
  $$ select count(*) from public.verification_requests $$,
  'permission denied for table verification_requests',
  'verification_requests hâlâ istemciye tamamen kapalı (onaylı/reddedilmiş fark etmez)'
);

-- ---------------------------------------------------------------------
-- Red simülasyonu (U2 için ayrı başvuru) — get_my_verification_status artık
-- 'rejected' döndürmeli, önceki davranışta bu 'none' ile ayırt edilemezdi.
-- ---------------------------------------------------------------------
SELECT lives_ok(
  $$ select public.request_verification('44400000-0000-0000-0000-000000000001/selfie.webp') $$,
  'U2 doğrulama başvurusu yapabilir'
);
SELECT tests.clear_authentication();

update public.verification_requests
  set status = 'rejected', reviewed_at = now()
  where profile_id = '44400000-0000-0000-0000-000000000001';

SELECT tests.authenticate_as('44400000-0000-0000-0000-000000000001');
SELECT is(
  public.get_my_verification_status(),
  'rejected',
  'get_my_verification_status: red sonrası ''rejected'' döner (artık ''none''dan ayırt edilebiliyor)'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
