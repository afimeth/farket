-- v4.1 sonraki fazlar, Faz 5: get_quiz_radar + get_weekly_digest.

BEGIN;
SELECT plan(7);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('55500000-0000-0000-0000-000000000000', 'target@test.local');
SELECT tests.create_supabase_user('55500000-0000-0000-0000-000000000001', 'v1@test.local');
SELECT tests.create_supabase_user('55500000-0000-0000-0000-000000000002', 'v2@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('55500000-0000-0000-0000-000000000000', 'T',  '1995-01-01', 'female', 900001, 'published'),
  ('55500000-0000-0000-0000-000000000001', 'V1', '1994-01-01', 'male',   900001, 'published'),
  ('55500000-0000-0000-0000-000000000002', 'V2', '1994-01-01', 'male',   900001, 'published');

-- Havuz start_quiz'in yeni 1. perde hedefiyle (2 kolay + 2 orta + 1 zor)
-- birebir aynı boyutta tutuluyor ki seçim rastgele olmasın (havuk == hedef
-- olunca hepsi seçilir) — testin "990001 her iki viewer'a da gösterildi"
-- gibi determinist beklentileri bunu gerektiriyor.
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 990000, 'Kalıp soru ' || g, 1, case when g<=2 then 'easy' when g<=4 then 'medium' else 'hard' end
from generate_series(1,5) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 991000, g + 990000, 'A', 1 from generate_series(1,5) g
union all
select g + 992000, g + 990000, 'B', 2 from generate_series(1,5) g;
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select '55500000-0000-0000-0000-000000000000', g + 990000, g + 991000,
       case when g<=2 then 'easy' when g<=4 then 'medium' else 'hard' end
from generate_series(1,5) g;
insert into public.taxonomies (id, name, question_body) overriding system value values (990101, 'Meslek', 'Ne iş yapar?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (990101, 990101, 'A'), (990102, 990101, 'B'), (990103, 990101, 'C');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
values (990101,990102),(990102,990101),(990101,990103),(990103,990101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (990201, 'Zor 1', 2, 'hard', 990101), (990202, 'Zor 2', 2, 'hard', 990101);
insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('55500000-0000-0000-0000-000000000000', 990201, 990101, 'hard'),
  ('55500000-0000-0000-0000-000000000000', 990202, 990101, 'hard');
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (990299, 'Zor 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (990391, 990299, 'A', 1), (990392, 990299, 'B', 2);
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
values ('55500000-0000-0000-0000-000000000000', 990299, 990391, 'hard');
insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('55500000-0000-0000-0000-000000000000', 'height_cm', 170, true);
insert into public.custom_questions (id, profile_id, body)
values ('55600000-0000-0000-0000-000000000001', '55500000-0000-0000-0000-000000000000', 'Soru?');
insert into public.custom_options (id, question_id, body, position)
values ('55700000-0000-0000-0000-000000000001', '55600000-0000-0000-0000-000000000001', 'X', 1),
       ('55700000-0000-0000-0000-000000000002', '55600000-0000-0000-0000-000000000001', 'Y', 2);
update public.custom_questions set correct_option_id = '55700000-0000-0000-0000-000000000001'
  where id = '55600000-0000-0000-0000-000000000001';

create or replace function tests.pick_wrong_rd(p_attempt_id uuid, p_position int, p_correct text)
returns text language sql as $$
  select opt ->> 'id'
  from public.attempt_questions aq, jsonb_array_elements(aq.shown_option_ids -> 'options') opt
  where aq.attempt_id = p_attempt_id and aq.position = p_position and (opt ->> 'id') <> p_correct
  limit 1;
$$;

create temp table ca (viewer_id uuid, attempt_id uuid, position int, template_id int, correct_option_id text);
grant select on ca to authenticated;

-- Her iki viewer da 990001 kalıbını (ilk kolay soru) BİLEREK yanlış
-- cevaplar, geri kalan her şeyi doğru -> 990001'in miss_count'u = 2,
-- en zor soru olarak öne çıkmalı.
do $$
declare
  v_viewer uuid;
  v_target uuid := '55500000-0000-0000-0000-000000000000';
  v_attempt uuid;
  v_pos int;
  v_tmpl int;
  v_correct text;
  i int;
begin
  for i in 1..2 loop
    v_viewer := ('55500000-0000-0000-0000-00000000000' || i)::uuid;
    perform tests.authenticate_as(v_viewer);
    v_attempt := (public.start_quiz(v_target) ->> 'attempt_id')::uuid;
    perform tests.clear_authentication();

    insert into ca (viewer_id, attempt_id, position, template_id, correct_option_id)
      select v_viewer, v_attempt, position, template_id, correct_option_id
      from public.attempt_questions where attempt_id = v_attempt;

    perform tests.authenticate_as(v_viewer);
    for v_pos in 1..10 loop
      select template_id, correct_option_id into v_tmpl, v_correct
        from ca where viewer_id = v_viewer and attempt_id = v_attempt and position = v_pos;
      if v_tmpl = 990001 then
        perform public.submit_answer(v_attempt, v_pos, tests.pick_wrong_rd(v_attempt, v_pos, v_correct));
      else
        perform public.submit_answer(v_attempt, v_pos, v_correct);
      end if;
    end loop;
    perform tests.clear_authentication();
  end loop;
end $$;

SELECT tests.authenticate_as('55500000-0000-0000-0000-000000000000');

-- ---------------------------------------------------------------------
-- get_quiz_radar
-- ---------------------------------------------------------------------
SELECT is(
  jsonb_path_query_first(public.get_quiz_radar(), '$[*] ? (@.template_id == 990001)') ->> 'shown_count',
  '2',
  '990001, iki viewer''a da gösterildiği için shown_count=2'
);

SELECT is(
  jsonb_path_query_first(public.get_quiz_radar(), '$[*] ? (@.template_id == 990001)') ->> 'correct_rate',
  '0',
  '990001, her iki viewer''dan da yanlış aldığı için correct_rate=0'
);

SELECT is(
  (select count(*) from jsonb_array_elements(public.get_quiz_radar()) e
     where (e ->> 'template_id')::int <> 990001 and (e ->> 'correct_rate')::int < 100),
  0::bigint,
  '990001 dışındaki tüm sorular her iki viewer''dan da doğru aldığı için correct_rate=100'
);

SELECT is(
  jsonb_array_length(public.get_quiz_radar()),
  8,
  'get_quiz_radar 8 kalıp sorunun (5 act1 + 3 act2-zor) hepsini listeliyor, serbest/künye soruları (template_id yok) hariç'
);

-- ---------------------------------------------------------------------
-- get_weekly_digest
-- ---------------------------------------------------------------------
SELECT is(
  (public.get_weekly_digest() ->> 'attempts_count')::int,
  2,
  'Son 7 günde 2 deneme yapıldı'
);

SELECT is(
  (public.get_weekly_digest() ->> 'passed_count')::int,
  2,
  'İki deneme de geçti (9/10 skorla, her ikisi de tier açtı)'
);

SELECT is(
  (public.get_weekly_digest() -> 'hardest_question') ->> 'body',
  'Kalıp soru 1',
  'En çok takılınan soru doğru tespit edildi (990001 = ''Kalıp soru 1'', miss_count=2)'
);

SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
