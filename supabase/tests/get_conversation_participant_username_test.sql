-- Bugfix: mesajlaşma ekranında karşı tarafın @handle'ının "@?" olarak
-- görünmesi sorunu. get_conversation_participant_username() konuşmanın
-- diğer tarafının username'ini döndürmeli; profiles tablosuna doğrudan
-- erişim RLS'ce hâlâ kapalı olmalı.

BEGIN;
SELECT plan(5);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('99990000-0000-0000-0000-000000000001', 'a@test.local');
SELECT tests.create_supabase_user('99990000-0000-0000-0000-000000000002', 'b@test.local');
SELECT tests.create_supabase_user('99990000-0000-0000-0000-000000000003', 'stranger@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status, username)
values
  ('99990000-0000-0000-0000-000000000001', 'A', '1994-01-01', 'male',   900001, 'published', 'kullanici_a'),
  ('99990000-0000-0000-0000-000000000002', 'B', '1994-01-01', 'female', 900001, 'published', 'kullanici_b'),
  ('99990000-0000-0000-0000-000000000003', 'C', '1994-01-01', 'male',   900001, 'published', 'kullanici_c');

insert into public.conversations (id, participant_a, participant_b, status)
values ('99991000-0000-0000-0000-000000000001', '99990000-0000-0000-0000-000000000001',
        '99990000-0000-0000-0000-000000000002', 'accepted');

-- ---------------------------------------------------------------------
-- 1) Katılımcı A, karşı tarafın (B) username'ini alabilir.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('99990000-0000-0000-0000-000000000001');
SELECT is(
  public.get_conversation_participant_username('99991000-0000-0000-0000-000000000001'),
  'kullanici_b',
  'A, konuşmadaki karşı tarafın (B) username''ini alabiliyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 2) Katılımcı B (diğer yön), karşı tarafın (A) username'ini alabilir.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('99990000-0000-0000-0000-000000000002');
SELECT is(
  public.get_conversation_participant_username('99991000-0000-0000-0000-000000000001'),
  'kullanici_a',
  'B, konuşmadaki karşı tarafın (A) username''ini alabiliyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 3) Konuşmanın tarafı olmayan biri (stranger) reddedilir.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('99990000-0000-0000-0000-000000000003');
SELECT throws_matching(
  $$ select public.get_conversation_participant_username('99991000-0000-0000-0000-000000000001') $$,
  'Bu konuşma sana ait değil',
  'Konuşmanın tarafı olmayan biri username sorgulayamaz'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 4) Var olmayan bir conversation_id de aynı şekilde reddedilir.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('99990000-0000-0000-0000-000000000001');
SELECT throws_matching(
  $$ select public.get_conversation_participant_username('99991000-0000-0000-0000-000000000099') $$,
  'Bu konuşma sana ait değil',
  'Var olmayan conversation_id de reddediliyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 5) Regresyon: profiles tablosuna doğrudan erişim hâlâ RLS'ce kapalı
-- (bu bug'ın kök nedeniydi — RPC'nin kendisi bunu bypass etmiyor,
-- yalnızca dar kapsamlı bir SECURITY DEFINER yol açıyor).
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('99990000-0000-0000-0000-000000000001');
SELECT is(
  (select count(*) from public.profiles where id = '99990000-0000-0000-0000-000000000002'),
  0::bigint,
  'profiles tablosuna doğrudan sorgu hâlâ yalnızca kendi satırını görüyor (RLS bozulmadı)'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
