-- Brifing v3, bölüm 8: güvenlik testleri.
-- Bu adımda (şema + RLS, bölüm 9'un 1-3. adımları) henüz sunucu
-- fonksiyonları yok. Fonksiyona bağlı yeni testler (farklı şehirde profil
-- görme, 24 saat şehir değişimi, atlanmış profilin destede çıkmaması)
-- discover_profiles/set_city yazıldığında eklenecek.

BEGIN;
SELECT plan(29);

-- ---------------------------------------------------------------------
-- Sabit test kimlikleri
--   Şehir 1 = İstanbul
--   A = 11111111-...-1 : hedef profil (künye, foto, custom soru sahibi)
--   B = 22222222-...-2 : A'yı quizleyen viewer, aktif denemesi var
--   C = 33333333-...-3 : hiçbir ilişkisi olmayan üçüncü kullanıcı
-- ---------------------------------------------------------------------
insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('11111111-1111-1111-1111-111111111111', 'a@test.local');
SELECT tests.create_supabase_user('22222222-2222-2222-2222-222222222222', 'b@test.local');
SELECT tests.create_supabase_user('33333333-3333-3333-3333-333333333333', 'c@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('11111111-1111-1111-1111-111111111111', 'A', '1995-01-01', 'female', 900001, 'published'),
  ('22222222-2222-2222-2222-222222222222', 'B', '1994-01-01', 'male',   900001, 'published'),
  ('33333333-3333-3333-3333-333333333333', 'C', '1993-01-01', 'male',   900001, 'published');

insert into public.identity_card (profile_id, show_name)
values ('11111111-1111-1111-1111-111111111111', true);

insert into public.photos (id, profile_id, position, storage_path_thumb, storage_path_full)
values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 1, 'private/a/1_thumb.webp', 'private/a/1_full.webp');

-- Soru altyapısı: bir sabit şıklı kalıp + bir taksonomi.
-- NOT: id'ler yüksek bir aralıkta (910000+) seçildi — production seed
-- migration'ı question_templates/taxonomies/taxonomy_items'ı 1'den
-- başlayarak dolduruyor, çakışmasın diye.
insert into public.question_templates (id, body, act, default_difficulty)
overriding system value
values (910001, 'Bu fotoğraf nerede çekildi?', 1, 'easy');

insert into public.template_options (id, template_id, body, position)
overriding system value
values (910001, 910001, 'Sahil', 1), (910002, 910001, 'Dağ', 2);

insert into public.taxonomies (id, name, question_body)
overriding system value
values (910001, 'Meslek', 'Bu kişinin mesleği ne?');

insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id)
overriding system value
values (910002, 'Bu kişinin mesleği ne?', 1, 'medium', 910001);

insert into public.taxonomy_items (id, taxonomy_id, label)
overriding system value
values (910001, 910001, 'Öğretmen'), (910002, 910001, 'Mühendis'), (910003, 910001, 'Doktor');

insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
values (910001, 910002), (910002, 910001);

-- A'nın kendi custom sorusu (act 2).
insert into public.custom_questions (id, profile_id, body)
values ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'En sevdiğim renk?');

insert into public.custom_options (id, question_id, body, position)
values
  ('cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'Mavi', 1),
  ('cccccccc-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000001', 'Yeşil', 2);

update public.custom_questions set correct_option_id = 'cccccccc-0000-0000-0000-000000000001'
  where id = 'bbbbbbbb-0000-0000-0000-000000000001';

-- template_stats: global istatistik satırı.
insert into public.template_stats (template_id, option_id, selected_count)
values (910001, 910001, 10);

-- B'nin A'ya karşı aktif denemesi.
insert into public.quiz_attempts (id, viewer_id, target_profile_id, status)
values ('dddddddd-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111', 'in_progress');

insert into public.attempt_questions (attempt_id, position, template_id, shown_option_ids, correct_option_id)
values (
  'dddddddd-0000-0000-0000-000000000001', 1, 910001,
  '{"question_body": "Bu fotoğraf nerede çekildi?", "options": [{"id": "910001", "body": "Sahil"}, {"id": "910002", "body": "Dağ"}]}'::jsonb,
  '910001'
);

insert into public.attempt_answers (attempt_id, question_position, selected_option_id, is_correct)
values ('dddddddd-0000-0000-0000-000000000001', 1, '910001', true);

insert into public.conversations (id, participant_a, participant_b, status)
values ('eeeeeeee-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222', 'pending');

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 0) Genel: public şemasındaki her tabloda RLS açık
-- ---------------------------------------------------------------------
SELECT ok(
  (select bool_and(c.relrowsecurity) from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'),
  'public şemasındaki tüm tablolarda RLS açık'
);

-- ---------------------------------------------------------------------
-- 1) profiles: başka kullanıcının profilini okuma/değiştirme
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');

SELECT is(
  (select count(*) from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  0::bigint,
  'B, A''nın profiline doğrudan select ile erişemez'
);

SELECT is(
  (select count(*) from public.profiles where id = '22222222-2222-2222-2222-222222222222'),
  1::bigint,
  'B kendi profilini görebilir'
);

WITH updated AS (
  UPDATE public.profiles SET display_name = 'hack'
    WHERE id = '11111111-1111-1111-1111-111111111111'
    RETURNING 1
)
SELECT is(
  (select count(*) from updated),
  0::bigint,
  'B, A''nın profilini update edemez (RLS satırı filtreler)'
);

-- ---------------------------------------------------------------------
-- 2) identity_card: doğrudan select — sahibi hariç kimse
-- ---------------------------------------------------------------------
SELECT is(
  (select count(*) from public.identity_card where profile_id = '11111111-1111-1111-1111-111111111111'),
  0::bigint,
  'B, A''nın identity_card''ına doğrudan select atamaz'
);

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333');
SELECT is(
  (select count(*) from public.identity_card where profile_id = '11111111-1111-1111-1111-111111111111'),
  0::bigint,
  'C, A''nın identity_card''ını okuyamaz'
);

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111');
SELECT is(
  (select count(*) from public.identity_card where profile_id = '11111111-1111-1111-1111-111111111111'),
  1::bigint,
  'A kendi identity_card''ını okuyabilir'
);

-- ---------------------------------------------------------------------
-- 3) taksonomi havuzu ve komşuluk: hiç kimse (bölüm 8 yeni testler)
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ select count(*) from public.taxonomy_items $$,
  'permission denied for table taxonomy_items',
  'Taksonomi havuzunun tamamını çekmeyi dene: A (profil sahibi) bile başaramaz'
);

SELECT throws_ok(
  $$ select count(*) from public.taxonomy_adjacency $$,
  'permission denied for table taxonomy_adjacency',
  'taxonomy_adjacency tablosunu okumayı dene: başarısız olmalı'
);

-- ---------------------------------------------------------------------
-- 4) profile_template_answers ve template_stats: tamamen kapalı
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ select count(*) from public.profile_template_answers $$,
  'permission denied for table profile_template_answers',
  'profile_template_answers istemciye tamamen kapalı'
);

SELECT throws_ok(
  $$ select count(*) from public.template_stats $$,
  'permission denied for table template_stats',
  'template_stats istemciye tamamen kapalı (global, service role)'
);

-- ---------------------------------------------------------------------
-- 5) custom_questions.correct_option_id: sahibi dahil kimse okuyamaz
-- ---------------------------------------------------------------------
SELECT is(
  (select count(*) from public.custom_questions where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  1::bigint,
  'A, kendi custom sorusunun body/is_active gibi alanlarını okuyabilir'
);

SELECT throws_ok(
  $$ select correct_option_id from public.custom_questions where id = 'bbbbbbbb-0000-0000-0000-000000000001' $$,
  'permission denied for table custom_questions',
  'A, kendi yazdığı sorunun correct_option_id''ını bile geri okuyamaz (sütun bazlı GRANT yok)'
);

SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');
SELECT is(
  (select count(*) from public.custom_questions where id = 'bbbbbbbb-0000-0000-0000-000000000001'),
  0::bigint,
  'B (sahibi değil), A''nın custom sorusunu hiç göremez'
);

-- ---------------------------------------------------------------------
-- 6) attempt_questions.correct_option_id: viewer bile okuyamaz
-- ---------------------------------------------------------------------
SELECT is(
  (select count(*) from public.attempt_questions where attempt_id = 'dddddddd-0000-0000-0000-000000000001'),
  1::bigint,
  'B, kendi aktif denemesine atanmış soruyu (correct_option_id hariç) görebilir'
);

SELECT throws_ok(
  $$ select correct_option_id from public.attempt_questions where attempt_id = 'dddddddd-0000-0000-0000-000000000001' $$,
  'permission denied for table attempt_questions',
  'B, kendi denemesinin doğru cevabını (correct_option_id) okuyamaz'
);

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333');
SELECT is(
  (select count(*) from public.attempt_questions where attempt_id = 'dddddddd-0000-0000-0000-000000000001'),
  0::bigint,
  'C, kendisine ait olmayan bir denemenin sorularını göremez'
);

-- ---------------------------------------------------------------------
-- 7) quiz_attempts: yalnızca viewer kendi denemesini görür (hedef göremez)
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');
SELECT is(
  (select count(*) from public.quiz_attempts where id = 'dddddddd-0000-0000-0000-000000000001'),
  1::bigint,
  'B (viewer) kendi denemesini görebilir'
);

SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111');
SELECT is(
  (select count(*) from public.quiz_attempts where id = 'dddddddd-0000-0000-0000-000000000001'),
  0::bigint,
  'A (hedef profil) kendisi hakkındaki quiz_attempts satırını göremez'
);

-- ---------------------------------------------------------------------
-- 8) blocks / reports: kimlik taklidi denemesi
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');
SELECT lives_ok(
  $$ insert into public.blocks (blocker_id, blocked_id)
     values ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333') $$,
  'B kendi adına engelleme kaydı oluşturabilir'
);

SELECT throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id)
     values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111') $$,
  'new row violates row-level security policy for table "blocks"',
  'B, başkasının adına engelleme kaydı oluşturamaz'
);

SELECT throws_ok(
  $$ insert into public.reports (reporter_id, reported_profile_id, reason)
     values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'spam') $$,
  'new row violates row-level security policy for table "reports"',
  'B, A''nın adına şikayet oluşturamaz'
);

-- ---------------------------------------------------------------------
-- 9) daily_quotas: doğrudan yazma denemesi
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ insert into public.daily_quotas (user_id, date, quiz_credits_used)
     values ('22222222-2222-2222-2222-222222222222', current_date, 999) $$,
  'permission denied for table daily_quotas',
  'B, kendi kotasını doğrudan yazarak değiştiremez'
);

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 10) DB seviyesinde dayatılan bütünlük kısıtları
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ insert into public.attempt_answers (attempt_id, question_position, selected_option_id, is_correct)
     values ('dddddddd-0000-0000-0000-000000000001', 1, '2', false) $$,
  'duplicate key value violates unique constraint "attempt_answers_pkey"',
  'Aynı soru pozisyonu aynı denemede ikinci kez cevaplanamaz (PK kısıtı)'
);

SELECT throws_ok(
  $$ insert into public.quiz_attempts (viewer_id, target_profile_id)
     values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111') $$,
  'duplicate key value violates unique constraint "quiz_attempts_viewer_target_round_attempt_key"',
  'Aynı tur içinde aynı hedef profile aynı attempt_no ile ikinci kez quiz denemesi açılamaz (bağlantı turları: UNIQUE artık (viewer, target, round_no, attempt_no) üzerinde)'
);

-- v4.1: UNIQUE kısıtı tek başına sınırsız deneme kapısı açmasın diye
-- (attempt_no = 3, 4, 5…) ayrı bir CHECK kısıtı var — retry mekaniğinin
-- brute-force koruması bu ikisine BİRLİKTE dayanıyor.
SELECT throws_ok(
  $$ insert into public.quiz_attempts (viewer_id, target_profile_id, attempt_no)
     values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 3) $$,
  'new row for relation "quiz_attempts" violates check constraint "quiz_attempts_attempt_no_max"',
  'Üçüncü deneme (attempt_no = 3) CHECK kısıtıyla reddedilir'
);

SELECT throws_ok(
  $$ update public.custom_questions set correct_option_id = 'cccccccc-0000-0000-0000-000000000099'
     where id = 'bbbbbbbb-0000-0000-0000-000000000001' $$,
  'correct_option_id, aynı custom_questions satırına ait bir custom_options satırı değil',
  'correct_option_id, var olmayan/başka soruya ait bir custom_options satırına işaret edemez (trigger)'
);

SELECT throws_ok(
  $$ insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
     values ('eeeeeeee-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
             repeat('x', 51), 50) $$,
  'new row for relation "messages" violates check constraint "messages_check"',
  '50 karakter sınırındayken 51 karakterlik mesaj CHECK kısıtına takılır'
);

SELECT throws_ok(
  $$ insert into public.template_options (template_id, body, position)
     values (910002, 'Yanlış yerde şık', 1) $$,
  'template_options yalnızca taxonomy_id boş olan question_templates için eklenebilir',
  'template_options, taxonomy_id dolu bir template''a eklenemez (trigger)'
);

SELECT * FROM finish();
ROLLBACK;
