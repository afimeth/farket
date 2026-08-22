-- Brifing v3, bölüm 9 adım 5: pick_distractors + start_quiz testleri.

BEGIN;
SELECT plan(10);

-- ---------------------------------------------------------------------
-- Fixture: A (hedef, tam donanımlı: 7 act1 + 2 act2-zor + 5 serbest soru),
-- B (viewer), C (ilişkisiz).
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

insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('11111111-1111-1111-1111-111111111111', 'height_cm', 170, true);

-- NOT: id'ler 930000+ aralığında — production seed migration'ıyla
-- çakışmasın diye.
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 930000, 'Kalıp soru ' || g, 1, 'easy' from generate_series(1, 7) g;

insert into public.template_options (id, template_id, body, position) overriding system value
select g + 931000, g + 930000, 'Şık A', 1 from generate_series(1, 7) g
union all
select g + 932000, g + 930000, 'Şık B', 2 from generate_series(1, 7) g;

-- 3 kolay + 3 orta + 1 zor: start_quiz'in katmanlı çekilişi bunu gerektirir.
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select '11111111-1111-1111-1111-111111111111', g + 930000, g + 931000,
       case when g <= 3 then 'easy' when g <= 6 then 'medium' else 'hard' end
from generate_series(1, 7) g;

insert into public.taxonomies (id, name, question_body) overriding system value
values (930101, 'Meslek', 'Mesleği ne?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (930101, 930101, 'Öğretmen'), (930102, 930101, 'Mühendis'), (930103, 930101, 'Doktor');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
values (930101, 930102), (930102, 930101), (930101, 930103), (930103, 930101);

insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (930201, 'Zor soru 1', 2, 'hard', 930101), (930202, 'Zor soru 2', 2, 'hard', 930101);

insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('11111111-1111-1111-1111-111111111111', 930201, 930101, 'hard'),
  ('11111111-1111-1111-1111-111111111111', 930202, 930101, 'hard');

-- 3. bir act2-zor soru: start_quiz'in 2. faz'ı yalnızca 1 custom + 1 künye
-- sorusunu garanti ediyor, kalanı act2-zor havuzundan dolduruyor (2 zor
-- soru tek başına yetmez: 1+1+2=4 < 5).
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (930299, 'Zor soru 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (930391, 930299, 'Şık A', 1), (930392, 930299, 'Şık B', 2);
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
values ('11111111-1111-1111-1111-111111111111', 930299, 930391, 'hard');

insert into public.custom_questions (id, profile_id, body)
values ('c0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Serbest 1');
insert into public.custom_options (id, question_id, body, position)
values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'X', 1),
  ('c1000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 'Y', 2);
update public.custom_questions set correct_option_id = 'c1000000-0000-0000-0000-000000000001'
  where id = 'c0000000-0000-0000-0000-000000000001';

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 1) pick_distractors istemciden hiç çağrılamaz.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('11111111-1111-1111-1111-111111111111');
SELECT throws_ok(
  $$ select public.pick_distractors(930101, 930101, 'hard') $$,
  'permission denied for function pick_distractors',
  'pick_distractors, authenticated rolünden doğrudan çağrılamaz'
);

-- ---------------------------------------------------------------------
-- 2) start_quiz mutlu senaryo: B, A'ya quiz başlatır.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');

-- start_quiz tek bir kez çağrılabilir (UNIQUE kısıtı); üç ayrı kontrolü de
-- (soru sayısı, DB'ye yazılan satır sayısı, correct_option_id sızıntısı
-- yokluğu) TEK çağrının sonucundan yapmak için geçici tabloya alıyoruz.
CREATE TEMP TABLE quiz_result AS
  SELECT public.start_quiz('11111111-1111-1111-1111-111111111111') AS payload;

SELECT is(
  (select jsonb_array_length(payload -> 'questions') from quiz_result),
  10,
  'start_quiz tam 10 soru döner'
);

SELECT is(
  (select count(*) from public.attempt_questions aq
     join public.quiz_attempts qa on qa.id = aq.attempt_id
     where qa.viewer_id = '22222222-2222-2222-2222-222222222222'),
  10::bigint,
  'attempt_questions''a 10 satır yazılmış'
);

SELECT ok(
  (select payload::text from quiz_result) not ilike '%correct_option_id%',
  'dönen JSON içinde correct_option_id hiç geçmiyor'
);

SELECT throws_ok(
  $$ select public.start_quiz('11111111-1111-1111-1111-111111111111') $$,
  'Bu profile zaten bir deneme açtın',
  'Aynı profile ikinci kez quiz başlatılamaz'
);

-- ---------------------------------------------------------------------
-- 3) Kendi profiline quiz başlatma engeli.
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ select public.start_quiz('22222222-2222-2222-2222-222222222222') $$,
  'Kendi profiline quiz başlatamazsın',
  'B, kendi profiline quiz başlatamaz'
);

-- ---------------------------------------------------------------------
-- 4) Yayınlanmamış / var olmayan hedef.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333');
SELECT throws_ok(
  $$ select public.start_quiz('99999999-9999-9999-9999-999999999999') $$,
  'Hedef profil bulunamadı veya yayınlanmamış',
  'Var olmayan/yayınlanmamış hedefe quiz başlatılamaz'
);

-- ---------------------------------------------------------------------
-- 5) Engellenmiş kullanıcıya quiz başlatma engeli.
-- ---------------------------------------------------------------------
SELECT tests.clear_authentication();
insert into public.blocks (blocker_id, blocked_id)
values ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333');

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333');
SELECT throws_ok(
  $$ select public.start_quiz('11111111-1111-1111-1111-111111111111') $$,
  'Bu profille etkileşim engellenmiş',
  'C, kendisini engelleyen A''ya quiz başlatamaz'
);

-- ---------------------------------------------------------------------
-- 6) Gizlenmiş (ikinci şansı henüz başlatılmamış) profile quiz başlatma
-- engeli — v4.1: hidden_profiles artık start_retry ile retry_used=true
-- işaretlenmeden ikinci bir start_quiz'e izin vermiyor. Gerçekçi bir
-- durum kurmak için bitmiş bir 1. deneme (attempt_no=1) + eşlik eden
-- hidden_profiles satırı (retry_used=false) ekleniyor.
-- ---------------------------------------------------------------------
SELECT tests.clear_authentication();
insert into public.quiz_attempts (viewer_id, target_profile_id, attempt_no, status, score, checkpoint_passed, completed_at)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 1, 'completed', 4, true, now());
insert into public.hidden_profiles (viewer_id, target_profile_id, first_attempt_score, available_at, retry_cost, retry_used)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 4, now() + interval '3 days', 3, false);

-- Bloğu kaldır ki hata mesajı gizleme kontrolünden gelsin.
delete from public.blocks
  where blocker_id = '11111111-1111-1111-1111-111111111111' and blocked_id = '33333333-3333-3333-3333-333333333333';

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333');
SELECT throws_ok(
  $$ select public.start_quiz('11111111-1111-1111-1111-111111111111') $$,
  'Bu profile zaten bir deneme açtın',
  'İkinci şansı start_retry ile başlatılmamış bir profile tekrar quiz başlatılamaz'
);

-- ---------------------------------------------------------------------
-- 7) Yetersiz soru havuzu olan bir hedefe quiz başlatma engeli.
-- ---------------------------------------------------------------------
SELECT tests.clear_authentication();
SELECT tests.create_supabase_user('44444444-4444-4444-4444-444444444444', 'd@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values ('44444444-4444-4444-4444-444444444444', 'D', '1996-01-01', 'female', 900001, 'published');

SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333');
SELECT throws_ok(
  $$ select public.start_quiz('44444444-4444-4444-4444-444444444444') $$,
  'Hedef profilin 1. perde için soru havuzu yetersiz (en az 5 kalıp soru cevaplanmış olmalı)',
  'Hiç soru seçmemiş bir profile quiz başlatılamaz'
);

SELECT * FROM finish();
ROLLBACK;
