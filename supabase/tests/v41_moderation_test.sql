-- v4.1 Migration 1: fotoğraf moderasyonu.
-- Kapsam: varsayılan 'approved', 3-farklı-kullanıcı şikayet eşiği (koda
-- gömülü değil, app_settings'ten okunuyor), publish_profile'ın rejected
-- fotoğrafı reddetmesi.

BEGIN;
SELECT plan(7);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

-- ---------------------------------------------------------------------
-- Grup A: şikayet eşiği.
-- ---------------------------------------------------------------------
SELECT tests.create_supabase_user('a1000000-0000-0000-0000-000000000000', 'm1@test.local');
SELECT tests.create_supabase_user('a1000000-0000-0000-0000-000000000001', 'r1@test.local');
SELECT tests.create_supabase_user('a1000000-0000-0000-0000-000000000002', 'r2@test.local');
SELECT tests.create_supabase_user('a1000000-0000-0000-0000-000000000003', 'r3@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('a1000000-0000-0000-0000-000000000000', 'M1', '1995-01-01', 'female', 900001, 'published'),
  ('a1000000-0000-0000-0000-000000000001', 'R1', '1994-01-01', 'male',   900001, 'published'),
  ('a1000000-0000-0000-0000-000000000002', 'R2', '1994-01-01', 'male',   900001, 'published'),
  ('a1000000-0000-0000-0000-000000000003', 'R3', '1994-01-01', 'male',   900001, 'published');

SELECT is(
  (select value from public.app_settings where key = 'photo_report_threshold'),
  '3',
  'Şikayet eşiği app_settings''te tutuluyor (koda gömülü değil), varsayılan 3'
);

-- moderation_status BELİRTİLMEDEN insert -> varsayılan artık 'approved'.
insert into public.photos (profile_id, position, storage_path_thumb, storage_path_full)
values (
  'a1000000-0000-0000-0000-000000000000', 1,
  'a1000000-0000-0000-0000-000000000000/p1_thumb.webp',
  'a1000000-0000-0000-0000-000000000000/p1_full.webp'
);

SELECT is(
  (select moderation_status from public.photos where profile_id = 'a1000000-0000-0000-0000-000000000000'),
  'approved',
  'Yeni yüklenen fotoğraf varsayılan olarak approved (sessiz blokaj düzeltmesi)'
);

insert into public.reports (reporter_id, reported_profile_id, reason)
values ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000000', 'spam');

SELECT is(
  (select moderation_status from public.photos where profile_id = 'a1000000-0000-0000-0000-000000000000'),
  'approved',
  '1 şikayetten sonra fotoğraf hâlâ approved (tek şikayet yeterli değil)'
);

insert into public.reports (reporter_id, reported_profile_id, reason)
values ('a1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000000', 'spam');

SELECT is(
  (select moderation_status from public.photos where profile_id = 'a1000000-0000-0000-0000-000000000000'),
  'approved',
  '2 farklı şikayetten sonra fotoğraf hâlâ approved'
);

-- Aynı kullanıcı (r1) ikinci kez şikayet etsin — distinct reporter sayısını
-- artırmamalı, eşiği tetiklememeli.
insert into public.reports (reporter_id, reported_profile_id, reason)
values ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000000', 'tekrar');

SELECT is(
  (select moderation_status from public.photos where profile_id = 'a1000000-0000-0000-0000-000000000000'),
  'approved',
  'Aynı kullanıcının tekrar şikayeti distinct reporter sayısını artırmıyor, eşik tetiklenmiyor'
);

insert into public.reports (reporter_id, reported_profile_id, reason)
values ('a1000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000000', 'spam');

SELECT is(
  (select moderation_status from public.photos where profile_id = 'a1000000-0000-0000-0000-000000000000'),
  'pending',
  '3. FARKLI kullanıcının şikayetinden sonra fotoğraf otomatik pending''e düşüyor'
);

-- ---------------------------------------------------------------------
-- Grup B: publish_profile, rejected fotoğrafı reddediyor.
-- ---------------------------------------------------------------------
SELECT tests.create_supabase_user('a2000000-0000-0000-0000-000000000000', 'm2@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, username, age_attested_at, status)
values ('a2000000-0000-0000-0000-000000000000', 'M2', '1995-01-01', 'female', 900001, 'm2_user', now(), 'draft');

insert into public.identity_card (profile_id, show_name) values ('a2000000-0000-0000-0000-000000000000', true);
insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('a2000000-0000-0000-0000-000000000000', 'height_cm', 170, true);

insert into public.photos (profile_id, position, storage_path_thumb, storage_path_full, moderation_status)
select 'a2000000-0000-0000-0000-000000000000', g,
       'a2000000-0000-0000-0000-000000000000/' || g || '_thumb.webp',
       'a2000000-0000-0000-0000-000000000000/' || g || '_full.webp',
       case when g = 3 then 'rejected' else 'approved' end
from generate_series(1, 5) g;

SELECT tests.authenticate_as('a2000000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.publish_profile() $$,
  'Onaylanmamış (bekleyen ya da reddedilen) bir fotoğrafın var — yayınlamadan önce tüm fotoğrafların onaylanmış olmalı.',
  'publish_profile, herhangi bir pozisyonda rejected fotoğraf varsa reddeder (act1/act2/custom eşiklerine hiç bakmadan)'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
