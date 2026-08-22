-- v4.1 Migration 2: additive kolonlar — özellikle profiles'taki yeni
-- sütunların (verified_at, tier, secret_card_*) istemciye KAPALI olduğunu
-- doğruluyor (blanket update grant sütun bazlıya düşürüldü).

BEGIN;
SELECT plan(8);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('b1000000-0000-0000-0000-000000000000', 'p1@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values ('b1000000-0000-0000-0000-000000000000', 'P', '1995-01-01', 'female', 900001, 'published');

SELECT tests.authenticate_as('b1000000-0000-0000-0000-000000000000');

SELECT throws_ok(
  $$ update public.profiles set verified_at = now() where id = 'b1000000-0000-0000-0000-000000000000' $$,
  'permission denied for table profiles',
  'Kullanıcı kendi verified_at''ını doğrudan set edemez (yalnızca elle/moderatör onayı)'
);

SELECT throws_ok(
  $$ update public.profiles set tier = 'premium' where id = 'b1000000-0000-0000-0000-000000000000' $$,
  'permission denied for table profiles',
  'Kullanıcı kendini premium yapamaz'
);

SELECT throws_ok(
  $$ update public.profiles set secret_card_type = 'note', secret_card_text = 'gizli not'
     where id = 'b1000000-0000-0000-0000-000000000000' $$,
  'permission denied for table profiles',
  'Kullanıcı secret_card alanlarını doğrudan set edemez (yalnızca set_secret_card() ile, ileride)'
);

SELECT lives_ok(
  $$ update public.profiles set display_name = 'Yeni İsim' where id = 'b1000000-0000-0000-0000-000000000000' $$,
  'İzinli sütunlar (display_name gibi) hâlâ güncellenebiliyor'
);

SELECT is(
  (select tier from public.profiles where id = 'b1000000-0000-0000-0000-000000000000'),
  'free',
  'Yeni profil varsayılan olarak tier=free'
);

SELECT throws_ok(
  $$ select count(*) from public.verification_requests $$,
  'permission denied for table verification_requests',
  'verification_requests istemciye tamamen kapalı'
);

SELECT throws_ok(
  $$ insert into public.verification_requests (profile_id, selfie_path)
     values ('b1000000-0000-0000-0000-000000000000', 'x/y.webp') $$,
  'permission denied for table verification_requests',
  'verification_requests''e doğrudan insert de kapalı'
);

SELECT tests.clear_authentication();

-- notifications.type CHECK listesi genişledi (postgres olarak, doğrudan).
SELECT lives_ok(
  $$ insert into public.notifications (user_id, type, payload)
     values ('b1000000-0000-0000-0000-000000000000', 'near_miss', '{}'::jsonb) $$,
  'notifications.type CHECK listesi yeni tipleri (near_miss vb.) kabul ediyor'
);

SELECT * FROM finish();
ROLLBACK;
