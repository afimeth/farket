-- profile_identity_attributes: flexible key-value identity facts (replaces
-- identity_card's fixed columns going forward) — RLS ownership, uniqueness,
-- and the value_text/value_numeric XOR + numeric-only-quiz-eligible checks.

BEGIN;
SELECT plan(8);

insert into public.cities (id, name) overriding system value values (900201, 'Test Şehir Attrs');

SELECT tests.create_supabase_user('77777777-0000-0000-0000-000000000000', 'g@test.local');
SELECT tests.create_supabase_user('88888888-0000-0000-0000-000000000000', 'h@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('77777777-0000-0000-0000-000000000000', 'G', '1994-01-01', 'male', 900201, 'draft'),
  ('88888888-0000-0000-0000-000000000000', 'H', '1994-01-01', 'male', 900201, 'draft');

SELECT tests.authenticate_as('77777777-0000-0000-0000-000000000000');

SELECT lives_ok(
  $$ insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
     values ('77777777-0000-0000-0000-000000000000', 'height_cm', 178, true) $$,
  'Sahip kendi sayısal künye alanını quiz-eligible olarak ekleyebilir'
);

SELECT throws_ok(
  $$ insert into public.profile_identity_attributes (profile_id, attribute_type, value_text, is_quiz_eligible)
     values ('77777777-0000-0000-0000-000000000000', 'school', 'ODTÜ', true) $$,
  'new row for relation "profile_identity_attributes" violates check constraint "profile_identity_attributes_check1"',
  'Metin alan quiz-eligible işaretlenemez (v1 kararı: yalnızca sayısal alanlar)'
);

SELECT lives_ok(
  $$ insert into public.profile_identity_attributes (profile_id, attribute_type, value_text, is_quiz_eligible)
     values ('77777777-0000-0000-0000-000000000000', 'school', 'ODTÜ', false) $$,
  'Metin alan quiz-eligible olmadan eklenebilir'
);

SELECT throws_ok(
  $$ insert into public.profile_identity_attributes (profile_id, attribute_type, value_text, value_numeric)
     values ('77777777-0000-0000-0000-000000000000', 'job', 'Mühendis', 5) $$,
  'new row for relation "profile_identity_attributes" violates check constraint "profile_identity_attributes_check"',
  'value_text ve value_numeric aynı anda dolu olamaz (XOR kısıtı)'
);

SELECT throws_ok(
  $$ insert into public.profile_identity_attributes (profile_id, attribute_type)
     values ('77777777-0000-0000-0000-000000000000', 'job') $$,
  'new row for relation "profile_identity_attributes" violates check constraint "profile_identity_attributes_check"',
  'value_text ve value_numeric ikisi de boş olamaz (XOR kısıtı)'
);

SELECT throws_ok(
  $$ insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric)
     values ('77777777-0000-0000-0000-000000000000', 'height_cm', 180) $$,
  'duplicate key value violates unique constraint "profile_identity_attributes_profile_id_attribute_type_key"',
  'Aynı profil aynı attribute_type''i iki kez ekleyemez'
);

SELECT tests.authenticate_as('88888888-0000-0000-0000-000000000000');

SELECT is(
  (select count(*) from public.profile_identity_attributes where profile_id = '77777777-0000-0000-0000-000000000000'),
  0::bigint,
  'Başka kullanıcı başkasının künye alanlarını okuyamaz (RLS)'
);

update public.profile_identity_attributes set value_numeric = 200
  where profile_id = '77777777-0000-0000-0000-000000000000' and attribute_type = 'height_cm';

SELECT tests.authenticate_as('77777777-0000-0000-0000-000000000000');

SELECT is(
  (select value_numeric from public.profile_identity_attributes
     where profile_id = '77777777-0000-0000-0000-000000000000' and attribute_type = 'height_cm'),
  178::numeric,
  'Başka kullanıcının update denemesi RLS yüzünden hiçbir satırı etkilemedi (değer hâlâ 178)'
);

SELECT * FROM finish();
ROLLBACK;
