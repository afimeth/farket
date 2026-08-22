-- Görev 2 kabul kriteri: aynı profil için 20 kez start_quiz çağrıldığında,
-- her denemede 1. perdenin (soru 1-5) zorluk dağılımı tam olarak 2/2/1.

BEGIN;
SELECT plan(3);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('66660000-0000-0000-0000-000000000000', 'target@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values ('66660000-0000-0000-0000-000000000000', 'Hedef', '1995-01-01', 'female', 900001, 'published');

insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('66660000-0000-0000-0000-000000000000', 'height_cm', 170, true);

-- NOT: id'ler 930000+ aralığında — production seed migration'ıyla
-- çakışmasın diye.
-- Bol miktarda act1 havuzu: 4 kolay + 4 orta + 2 zor (minimum 3/3/1'in
-- üzerinde, gerçek rastgelelik olsun diye).
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 930000, 'Kalıp soru ' || g, 1,
       case when g <= 4 then 'easy' when g <= 8 then 'medium' else 'hard' end
from generate_series(1, 10) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 931000, g + 930000, 'Şık A', 1 from generate_series(1, 10) g
union all
select g + 932000, g + 930000, 'Şık B', 2 from generate_series(1, 10) g;
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select '66660000-0000-0000-0000-000000000000', g + 930000, g + 931000,
       case when g <= 4 then 'easy' when g <= 8 then 'medium' else 'hard' end
from generate_series(1, 10) g;

-- act2-zor havuzu + 1 serbest soru.
insert into public.taxonomies (id, name, question_body) overriding system value values (930101, 'Meslek', 'Mesleği ne?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (930101, 930101, 'Öğretmen'), (930102, 930101, 'Mühendis'), (930103, 930101, 'Doktor');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id) values (930101, 930102), (930102, 930101), (930101, 930103), (930103, 930101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (930201, 'Zor soru 1', 2, 'hard', 930101), (930202, 'Zor soru 2', 2, 'hard', 930101);
insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('66660000-0000-0000-0000-000000000000', 930201, 930101, 'hard'),
  ('66660000-0000-0000-0000-000000000000', 930202, 930101, 'hard');

-- 3. bir act2-zor soru: start_quiz'in 2. faz'ı yalnızca 1 custom + 1 künye
-- sorusunu garanti ediyor, kalanı act2-zor havuzundan dolduruyor (2 zor
-- soru tek başına yetmez: 1+1+2=4 < 5).
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (930299, 'Zor soru 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (930391, 930299, 'Şık A', 1), (930392, 930299, 'Şık B', 2);
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
values ('66660000-0000-0000-0000-000000000000', 930299, 930391, 'hard');

insert into public.custom_questions (id, profile_id, body)
values ('c0000000-0000-0000-0000-000000000001', '66660000-0000-0000-0000-000000000000', 'Serbest 1');
insert into public.custom_options (id, question_id, body, position)
values
  ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'X', 1),
  ('c1000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 'Y', 2);
update public.custom_questions set correct_option_id = 'c1000000-0000-0000-0000-000000000001'
  where id = 'c0000000-0000-0000-0000-000000000001';

-- 20 ayrı viewer, hepsi hedefe karşı start_quiz çağırır.
create temp table runs (attempt_id uuid);

do $$
declare
  v_uid uuid;
  i     int;
  v_attempt_id uuid;
begin
  for i in 1..20 loop
    v_uid := ('77770000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid;
    perform tests.create_supabase_user(v_uid, 'v' || i || '@test.local');
    insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
      values (v_uid, 'V' || i, '1994-01-01', 'male', 900001, 'published');

    perform tests.authenticate_as(v_uid);
    v_attempt_id := (public.start_quiz('66660000-0000-0000-0000-000000000000') ->> 'attempt_id')::uuid;
    perform tests.clear_authentication();

    insert into runs (attempt_id) values (v_attempt_id);
  end loop;
end $$;

SELECT is(
  (select count(*) from runs),
  20::bigint,
  '20 viewer''ın da start_quiz çağrısı hatasız tamamlandı'
);

SELECT ok(
  (
    select bool_and(t.is_valid)
    from (
      select r.attempt_id,
             count(*) filter (where pta.difficulty = 'easy') = 2
             and count(*) filter (where pta.difficulty = 'medium') = 2
             and count(*) filter (where pta.difficulty = 'hard') = 1
             as is_valid
      from runs r
      join public.attempt_questions aq
        on aq.attempt_id = r.attempt_id and aq.position between 1 and 5
      join public.profile_template_answers pta
        on pta.template_id = aq.template_id and pta.profile_id = '66660000-0000-0000-0000-000000000000'
      group by r.attempt_id
    ) t
  ),
  '20 denemenin HEPSİNDE 1. perde zorluk dağılımı tam olarak 2 kolay + 2 orta + 1 zor'
);

-- Pozisyonların da karıştığını (her zaman aynı sırada olmadığını) doğrula:
-- 20 denemenin en az ikisinde 1. pozisyondaki template_id farklı olmalı.
SELECT ok(
  (select count(distinct aq.template_id) from runs r
     join public.attempt_questions aq on aq.attempt_id = r.attempt_id and aq.position = 1) > 1,
  'Pozisyon sırası da karışıyor (1. soru hep aynı zorluktan/şablondan gelmiyor)'
);

SELECT * FROM finish();
ROLLBACK;
