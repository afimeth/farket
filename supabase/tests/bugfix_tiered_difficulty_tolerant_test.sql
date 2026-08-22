-- BACKEND_BUG_zorluk_dagilimi.md raporunda tarif edilen senaryo:
-- kullanıcı 1. perdede toplam 7 kalıp soru cevaplıyor ama zorluk dağılımı
-- dengesiz (5 easy + 2 medium + 0 hard, hard havuzu tamamen boş).
-- 20260818122000_bugfix_tiered_difficulty_tolerant.sql'den ÖNCE bu
-- senaryoda start_quiz her zaman hata fırlatırdı; artık kalan havuzdan
-- 7'ye tamamlayıp devam etmeli.

BEGIN;
SELECT plan(4);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('88880000-0000-0000-0000-000000000000', 'target@test.local');
SELECT tests.create_supabase_user('88880000-0000-0000-0000-000000000001', 'viewer@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('88880000-0000-0000-0000-000000000000', 'Hedef',  '1995-01-01', 'female', 900001, 'published'),
  ('88880000-0000-0000-0000-000000000001', 'Viewer', '1994-01-01', 'male',   900001, 'published');

insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('88880000-0000-0000-0000-000000000000', 'height_cm', 170, true);

-- Rapordaki tam senaryo: 5 easy + 2 medium + 0 hard = 7 toplam, hard havuzu
-- tamamen boş.
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 940000, 'Kalıp soru ' || g, 1,
       case when g <= 5 then 'easy' else 'medium' end
from generate_series(1, 7) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 941000, g + 940000, 'Şık A', 1 from generate_series(1, 7) g
union all
select g + 942000, g + 940000, 'Şık B', 2 from generate_series(1, 7) g;
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select '88880000-0000-0000-0000-000000000000', g + 940000, g + 941000,
       case when g <= 5 then 'easy' else 'medium' end
from generate_series(1, 7) g;

-- act2-zor havuzu + 1 serbest soru (bu kısım senaryoyla ilgisiz, sadece
-- start_quiz'in tamamlanabilmesi için gerekli).
insert into public.taxonomies (id, name, question_body) overriding system value values (940101, 'Meslek', 'Mesleği ne?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (940101, 940101, 'Öğretmen'), (940102, 940101, 'Mühendis'), (940103, 940101, 'Doktor');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id) values (940101, 940102), (940102, 940101), (940101, 940103), (940103, 940101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (940201, 'Zor soru 1', 2, 'hard', 940101), (940202, 'Zor soru 2', 2, 'hard', 940101);
insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('88880000-0000-0000-0000-000000000000', 940201, 940101, 'hard'),
  ('88880000-0000-0000-0000-000000000000', 940202, 940101, 'hard');

-- 3. bir act2-zor soru: start_quiz'in 2. faz'ı yalnızca 1 custom + 1 künye
-- sorusunu garanti ediyor, kalanı act2-zor havuzundan dolduruyor (2 zor
-- soru tek başına yetmez: 1+1+2=4 < 5).
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (940299, 'Zor soru 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (940391, 940299, 'Şık A', 1), (940392, 940299, 'Şık B', 2);
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
values ('88880000-0000-0000-0000-000000000000', 940299, 940391, 'hard');

insert into public.custom_questions (id, profile_id, body)
values ('c2000000-0000-0000-0000-000000000001', '88880000-0000-0000-0000-000000000000', 'Serbest 1');
insert into public.custom_options (id, question_id, body, position)
values
  ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'X', 1),
  ('c3000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001', 'Y', 2);
update public.custom_questions set correct_option_id = 'c3000000-0000-0000-0000-000000000001'
  where id = 'c2000000-0000-0000-0000-000000000001';

SELECT tests.authenticate_as('88880000-0000-0000-0000-000000000001');

SELECT lives_ok(
  $$ select public.start_quiz('88880000-0000-0000-0000-000000000000') $$,
  'Hard havuzu tamamen boş (5 easy + 2 medium + 0 hard) olsa bile start_quiz artık hata fırlatmıyor'
);

SELECT is(
  (select count(*) from public.attempt_questions aq
     join public.quiz_attempts qa on qa.id = aq.attempt_id
     where qa.viewer_id = '88880000-0000-0000-0000-000000000001' and aq.position between 1 and 5),
  5::bigint,
  '1. perde yine de tam 5 soruyla tamamlanıyor (zorluk oranı garanti edilemese de)'
);

SELECT is(
  (select count(distinct aq.template_id) from public.attempt_questions aq
     join public.quiz_attempts qa on qa.id = aq.attempt_id
     where qa.viewer_id = '88880000-0000-0000-0000-000000000001' and aq.position between 1 and 5),
  5::bigint,
  'Seçilen 5 template_id birbirinden farklı (tekrar/çakışma yok)'
);

SELECT tests.clear_authentication();

-- Karşıt senaryo: gerçekten 7'den AZ kalıp sorusu cevaplanmışsa (wizard'ın
-- kendi "en az 7" şartı bile sağlanmamışsa) hata fırlatmaya devam etmeli.
SELECT tests.create_supabase_user('88880000-0000-0000-0000-000000000002', 'target2@test.local');
SELECT tests.create_supabase_user('88880000-0000-0000-0000-000000000003', 'viewer2@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('88880000-0000-0000-0000-000000000002', 'Hedef2',  '1995-01-01', 'female', 900001, 'published'),
  ('88880000-0000-0000-0000-000000000003', 'Viewer2', '1994-01-01', 'male',   900001, 'published');

insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 950000, 'Kalıp soru ' || g, 1, 'easy'
from generate_series(1, 4) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 951000, g + 950000, 'Şık A', 1 from generate_series(1, 4) g
union all
select g + 952000, g + 950000, 'Şık B', 2 from generate_series(1, 4) g;
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select '88880000-0000-0000-0000-000000000002', g + 950000, g + 951000, 'easy'
from generate_series(1, 4) g;

SELECT tests.authenticate_as('88880000-0000-0000-0000-000000000003');
SELECT throws_matching(
  $$ select public.start_quiz('88880000-0000-0000-0000-000000000002') $$,
  'en az 5 kalıp soru cevaplanmış olmalı',
  'Gerçekten 5''ten az kalıp sorusu cevaplanmışsa start_quiz hâlâ hata fırlatıyor'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
