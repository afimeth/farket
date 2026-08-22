-- Brifing v3, bölüm 9 adım 7: template_stats güncellemesi + taban oran
-- filtresi testleri.

BEGIN;
SELECT plan(5);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

-- NOT: id'ler 930000+ aralığında — production seed migration'ıyla
-- çakışmasın diye. 8 sabit şıklı act1 kalıp (930001-930008) — 930008
-- taban oranıyla pasifleştirilecek.
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 930000, 'Kalıp soru ' || g, 1, 'easy' from generate_series(1, 8) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 931000, g + 930000, 'Şık A', 1 from generate_series(1, 8) g
union all
select g + 932000, g + 930000, 'Şık B', 2 from generate_series(1, 8) g;

-- 1 taksonomi bazlı act2-zor kalıp (930201) — item_id kolunu test etmek için.
insert into public.taxonomies (id, name, question_body) overriding system value values (930101, 'Meslek', 'Mesleği ne?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (930101, 930101, 'Öğretmen'), (930102, 930101, 'Mühendis'), (930103, 930101, 'Doktor');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id) values (930101, 930102), (930102, 930101), (930101, 930103), (930103, 930101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (930201, 'Zor soru 1', 2, 'hard', 930101), (930202, 'Zor soru 2', 2, 'hard', 930101);

-- 3. bir act2-zor soru: start_quiz'in 2. faz'ı yalnızca 1 custom + 1 künye
-- sorusunu garanti ediyor, kalanı act2-zor havuzundan dolduruyor (2 zor
-- soru tek başına yetmez: 1+1+2=4 < 5).
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (930299, 'Zor soru 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (930391, 930299, 'Şık A', 1), (930392, 930299, 'Şık B', 2);

SELECT tests.create_supabase_user('88888888-0000-0000-0000-000000000000', 'h@test.local');
SELECT tests.create_supabase_user('99999999-0000-0000-0000-000000000001', 'i@test.local');
SELECT tests.create_supabase_user('99999999-0000-0000-0000-000000000002', 'j@test.local');
SELECT tests.create_supabase_user('99999999-0000-0000-0000-000000000003', 'k@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('88888888-0000-0000-0000-000000000000', 'H', '1994-01-01', 'male',   900001, 'published'),
  ('99999999-0000-0000-0000-000000000001', 'I', '1995-01-01', 'female', 900001, 'published'),
  ('99999999-0000-0000-0000-000000000002', 'J', '1994-01-01', 'male',   900001, 'published'),
  ('99999999-0000-0000-0000-000000000003', 'K', '1994-01-01', 'male',   900001, 'published');

insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('99999999-0000-0000-0000-000000000001', 'height_cm', 170, true);

-- I, 930001-930008 arası tüm act1 kalıpları + 930201/930202'yi seçmiş.
-- 930007-930008 "hard" — 930008 pasifleşince hâlâ 3 kolay/3 orta/1 zor
-- (yalnızca 930007) kalmalı ki start_quiz'in katmanlı çekilişi
-- başarısız olmasın.
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select '99999999-0000-0000-0000-000000000001', g + 930000, g + 931000,
       case when g <= 3 then 'easy' when g <= 6 then 'medium' else 'hard' end
from generate_series(1, 8) g;
insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('99999999-0000-0000-0000-000000000001', 930201, 930101, 'hard'),
  ('99999999-0000-0000-0000-000000000001', 930202, 930101, 'hard');
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
values ('99999999-0000-0000-0000-000000000001', 930299, 930391, 'hard');
insert into public.custom_questions (id, profile_id, body)
values ('c0000000-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000001', 'Serbest 1');
insert into public.custom_options (id, question_id, body, position)
values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'X', 1),
  ('c1000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 'Y', 2);
update public.custom_questions set correct_option_id = 'c1000000-0000-0000-0000-000000000001'
  where id = 'c0000000-0000-0000-0000-000000000001';

-- Taban oranı sınıra yaklaştırmak için 19 önceki seçimi doğrudan yazıyoruz
-- (gerçek geçmiş denemeleri simüle ediyor).
insert into public.template_stats (template_id, option_id, selected_count) values (930008, 931008, 19);

-- H'nin I'ya karşı "sahte" (start_quiz'i atlayan) minimal bir denemesi:
-- yalnızca template 930008'i position 1'e koyuyoruz, submit_answer'ı tek
-- başına test etmek için.
insert into public.quiz_attempts (id, viewer_id, target_profile_id)
values ('dddddddd-1111-0000-0000-000000000001', '88888888-0000-0000-0000-000000000000',
        '99999999-0000-0000-0000-000000000001');
insert into public.attempt_questions (attempt_id, position, template_id, shown_option_ids, correct_option_id)
values ('dddddddd-1111-0000-0000-000000000001', 1, 930008,
        '{"question_body": "Kalıp soru 8", "options": [{"id":"931008","body":"Şık A"},{"id":"932008","body":"Şık B"}]}'::jsonb,
        '931008');

-- Aynı şekilde template 930201 (taksonomi) için de ikinci bir sahte deneme.
insert into public.quiz_attempts (id, viewer_id, target_profile_id)
values ('dddddddd-1111-0000-0000-000000000002', '99999999-0000-0000-0000-000000000002',
        '99999999-0000-0000-0000-000000000001');
insert into public.attempt_questions (attempt_id, position, template_id, shown_option_ids, correct_option_id)
values ('dddddddd-1111-0000-0000-000000000002', 1, 930201,
        '{"question_body": "Zor soru 1", "options": [{"id":"930101","body":"Öğretmen"},{"id":"930102","body":"Mühendis"}]}'::jsonb,
        '930101');

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 1) submit_answer, sabit şıklı bir soruda template_stats.option_id
--    kolonunu günceller; taban oranı %55'i ve 20 örneklemi aşınca
--    question_templates.is_active false olur.
-- ---------------------------------------------------------------------
SELECT is(
  (select is_active from public.question_templates where id = 930008),
  true,
  'Kalıp 930008, 20. seçimden önce hâlâ aktif'
);

SELECT tests.authenticate_as('88888888-0000-0000-0000-000000000000');
SELECT public.submit_answer('dddddddd-1111-0000-0000-000000000001', 1, '931008');
SELECT tests.clear_authentication();

SELECT is(
  (select selected_count from public.template_stats where template_id = 930008 and option_id = 931008),
  20,
  'template_stats.option_id, 20. seçimle birlikte doğru şekilde artırıldı'
);

SELECT is(
  (select is_active from public.question_templates where id = 930008),
  false,
  '20 örneklemde %55''i aşan taban oranı, kalıbı pasifleştirir'
);

-- ---------------------------------------------------------------------
-- 2) submit_answer, taksonomi bazlı bir soruda template_stats.item_id
--    kolonunu günceller (option_id değil).
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('99999999-0000-0000-0000-000000000002');
SELECT public.submit_answer('dddddddd-1111-0000-0000-000000000002', 1, '930101');
SELECT tests.clear_authentication();

SELECT is(
  (select item_id from public.template_stats where template_id = 930201 and item_id = 930101),
  930101,
  'Taksonomi bazlı soruda template_stats.item_id kolonu dolduruluyor'
);

-- ---------------------------------------------------------------------
-- 3) start_quiz, pasifleşen kalıp 930008'i artık seçmiyor.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('99999999-0000-0000-0000-000000000003');
CREATE TEMP TABLE started_k AS SELECT public.start_quiz('99999999-0000-0000-0000-000000000001') AS payload;
SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.attempt_questions aq
     where aq.attempt_id = (select (payload ->> 'attempt_id')::uuid from started_k)
       and aq.template_id = 930008),
  0::bigint,
  'Pasifleşmiş kalıp 930008, yeni bir quiz''e hiç seçilmiyor'
);

SELECT * FROM finish();
ROLLBACK;
