-- Brifing v3, bölüm 9 adım 8 (Keşif) + bölüm 8'in daha önce ertelenen iki
-- testi: farklı şehirdeki profili keşifte görme, atlanmış profilin ana
-- destede tekrar çıkmaması.

BEGIN;
SELECT plan(14);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir A'), (900002, 'Test Şehir B');

SELECT tests.create_supabase_user('00000000-0000-0000-0000-000000000001', 'v@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-00000000000a', 'm@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-00000000000b', 'n@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-00000000000c', 'o@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-00000000000d', 'p@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-00000000000e', 'q@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-00000000000f', 'r@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-000000000010', 's@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-000000000011', 't@test.local');
SELECT tests.create_supabase_user('00000000-0000-0000-0000-000000000012', 'u@test.local');

-- V: viewer, İstanbul.
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-000000000001', 'V', '1994-01-01', 'male', 900001, 'v_user', 'published');

-- M: temiz, uygun bir hedef — görünmesi gereken tek profil.
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-00000000000a', 'M', '1995-01-01', 'female', 900001, 'm_user', 'published');

-- N: farklı şehir (Ankara).
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-00000000000b', 'N', '1995-01-01', 'female', 900002, 'n_user', 'published');

-- O: yayınlanmamış (draft).
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-00000000000c', 'O', '1995-01-01', 'female', 900001, 'o_user', 'draft');

-- P: engellenmiş (V, P'yi engellemiş).
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-00000000000d', 'P', '1995-01-01', 'female', 900001, 'p_user', 'published');

-- Q: gizlenmiş (3 ay, süre dolmamış).
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-00000000000e', 'Q', '1995-01-01', 'female', 900001, 'q_user', 'published');

-- R: atlanmış.
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-00000000000f', 'R', '1995-01-01', 'female', 900001, 'r_user', 'published');

-- S: zaten bir denemesi var.
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-000000000010', 'S', '1995-01-01', 'female', 900001, 's_user', 'published');

-- T: username henüz seçilmemiş.
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-000000000011', 'T', '1995-01-01', 'female', 900001, null, 'published');

-- U: kapak fotoğrafı (position 1, onaylı) yok.
insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values ('00000000-0000-0000-0000-000000000012', 'U', '1995-01-01', 'female', 900001, 'u_user', 'published');

-- M, N, O, P, Q, R, S, T'ye onaylı kapak fotoğrafı; U'ya bilerek verilmiyor.
insert into public.photos (profile_id, position, storage_path_thumb, storage_path_full, moderation_status)
select id, 1, 'private/' || id || '/1_thumb.webp', 'private/' || id || '/1_full.webp', 'approved'
from public.profiles
where id in (
  '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b',
  '00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000d',
  '00000000-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-00000000000f',
  '00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000011'
);

insert into public.blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000d');

insert into public.hidden_profiles (viewer_id, target_profile_id, first_attempt_score, available_at, retry_cost, retry_used)
values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000e', 0, now() + interval '3 months', 5, false);

insert into public.skipped_profiles (viewer_id, target_profile_id)
values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000f');

insert into public.quiz_attempts (viewer_id, target_profile_id)
values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000010');

SELECT tests.authenticate_as('00000000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------
-- 1) discover_profiles: yalnızca M görünmeli.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE deck AS SELECT public.discover_profiles(20) AS payload;

SELECT is(
  jsonb_array_length((select payload from deck)),
  1,
  'Keşif destesinde tam olarak bir profil var (yalnızca M uygun)'
);

SELECT is(
  (select payload -> 0 ->> 'id' from deck),
  '00000000-0000-0000-0000-00000000000a',
  'Destede görünen tek profil M'
);

SELECT is(
  (select (payload -> 0 ->> 'is_bot')::boolean from deck),
  false,
  'M bot değil, is_bot alanı false dönüyor'
);

SELECT ok(
  (select payload::text from deck) not like '%00000000-0000-0000-0000-00000000000b%',
  'Farklı şehirdeki N (Ankara) keşifte görünmüyor'
);

SELECT ok(
  (select payload::text from deck) not like '%00000000-0000-0000-0000-00000000000c%',
  'Yayınlanmamış (draft) O keşifte görünmüyor'
);

SELECT ok(
  (select payload::text from deck) not like '%00000000-0000-0000-0000-00000000000d%',
  'Engellenmiş P keşifte görünmüyor'
);

SELECT ok(
  (select payload::text from deck) not like '%00000000-0000-0000-0000-00000000000e%',
  'Gizlenmiş (3 ay) Q keşifte görünmüyor'
);

SELECT ok(
  (select payload::text from deck) not like '%00000000-0000-0000-0000-00000000000f%',
  'Daha önce atlanmış R keşifte görünmüyor'
);

SELECT ok(
  (select payload::text from deck) not like '%00000000-0000-0000-0000-000000000010%',
  'Zaten denemesi olan S keşifte görünmüyor'
);

SELECT ok(
  (select payload::text from deck) not like '%00000000-0000-0000-0000-000000000011%',
  'username''ı olmayan T keşifte görünmüyor'
);

SELECT ok(
  (select payload::text from deck) not like '%00000000-0000-0000-0000-000000000012%',
  'Kapak fotoğrafı olmayan U keşifte görünmüyor'
);

-- ---------------------------------------------------------------------
-- 2) skip_profile sonrası M destede kaybolur; unskip_profile ile geri gelir.
-- ---------------------------------------------------------------------
SELECT public.skip_profile('00000000-0000-0000-0000-00000000000a');

SELECT is(
  jsonb_array_length(public.discover_profiles(20)),
  0,
  'M atlanınca aynı sorguda tekrar çıkmıyor'
);

SELECT public.unskip_profile('00000000-0000-0000-0000-00000000000a');

SELECT is(
  jsonb_array_length(public.discover_profiles(20)),
  1,
  'unskip_profile sonrası M tekrar destede'
);

-- ---------------------------------------------------------------------
-- 3) get_public_profile: yalnızca gösterilebilir alanlar, künye alanları yok.
-- ---------------------------------------------------------------------
SELECT ok(
  (public.get_public_profile('00000000-0000-0000-0000-00000000000a')::text) not like '%display_name%'
  and (public.get_public_profile('00000000-0000-0000-0000-00000000000a')::text) not like '%birth_date%',
  'get_public_profile, display_name veya birth_date döndürmüyor'
);

SELECT * FROM finish();
ROLLBACK;
