-- reveal_identity testleri.

BEGIN;
SELECT plan(6);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('11111111-0000-0000-0000-000000000000', 'a@test.local');
SELECT tests.create_supabase_user('22222222-0000-0000-0000-000000000000', 'b@test.local');
SELECT tests.create_supabase_user('33333333-0000-0000-0000-000000000000', 'c@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('11111111-0000-0000-0000-000000000000', 'Ayşe', '1995-03-10', 'female', 900001, 'published'),
  ('22222222-0000-0000-0000-000000000000', 'B', '1994-01-01', 'male', 900001, 'published'),
  ('33333333-0000-0000-0000-000000000000', 'C', '1993-01-01', 'male', 900001, 'published');

-- A: yalnızca ismini açıyor, yaşını/mesleğini/şehrini/niyetini açmıyor.
-- identity_card artık yalnızca migration zamanındaki verinin backfill
-- kaynağı (bkz. 20260821020000_profile_identity_attributes.sql) — bu satır
-- migration'dan SONRA eklendiği için otomatik taşınmıyor, bu yüzden
-- reveal_identity'nin gerçekte okuduğu profile_identity_attributes'a da
-- doğrudan yazıyoruz.
insert into public.identity_card (profile_id, show_name, show_age, show_occupation, show_city, show_intent, occupation, intent)
values ('11111111-0000-0000-0000-000000000000', true, false, false, false, false, 'Mühendis', 'arkadaslik');

insert into public.profile_identity_attributes (profile_id, attribute_type, value_text, is_shown_on_reveal)
values ('11111111-0000-0000-0000-000000000000', 'name', 'Ayşe', true);

-- B: checkpoint'i henüz geçmemiş bir deneme.
insert into public.quiz_attempts (id, viewer_id, target_profile_id, checkpoint_passed)
values ('dddddddd-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000000',
        '11111111-0000-0000-0000-000000000000', false);

-- C: checkpoint'i geçmiş bir deneme.
insert into public.quiz_attempts (id, viewer_id, target_profile_id, checkpoint_passed)
values ('dddddddd-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000000',
        '11111111-0000-0000-0000-000000000000', true);

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 1) Checkpoint geçilmeden künye açılamaz.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.reveal_identity('dddddddd-0000-0000-0000-000000000001') $$,
  'Checkpoint geçilmeden künye açılamaz',
  'Checkpoint geçmeden reveal_identity çağrılamaz'
);

-- ---------------------------------------------------------------------
-- 2) Checkpoint geçilince: show_name=true → isim döner.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');

SELECT is(
  public.reveal_identity('dddddddd-0000-0000-0000-000000000002') ->> 'name',
  'Ayşe',
  'show_name=true olan isim döner'
);

-- ---------------------------------------------------------------------
-- 3) show_age/show_occupation/show_city/show_intent=false → dönmez.
-- ---------------------------------------------------------------------
SELECT ok(
  not (public.reveal_identity('dddddddd-0000-0000-0000-000000000002') ? 'age'),
  'show_age=false olan yaş dönmez'
);

SELECT ok(
  not (public.reveal_identity('dddddddd-0000-0000-0000-000000000002') ? 'occupation'),
  'show_occupation=false olan meslek dönmez'
);

-- ---------------------------------------------------------------------
-- 4) Sahiplik: B, C'nin denemesiyle künye açamaz.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.reveal_identity('dddddddd-0000-0000-0000-000000000002') $$,
  'Bu deneme sana ait değil',
  'B, C''nin denemesiyle künye açamaz'
);

-- ---------------------------------------------------------------------
-- 5) identity_reveals tekrar çağrılınca ikinci kez yazılmaz.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');
SELECT public.reveal_identity('dddddddd-0000-0000-0000-000000000002');
SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.identity_reveals
     where viewer_id = '33333333-0000-0000-0000-000000000000'
       and target_profile_id = '11111111-0000-0000-0000-000000000000'),
  1::bigint,
  'identity_reveals, tekrar çağrılara rağmen tek satır kalır'
);

SELECT * FROM finish();
ROLLBACK;
