-- v4.1 sonraki fazlar, Faz 2: bildirim ilerlemesi (quiz_progress) + kıl
-- payı (near_miss).

BEGIN;
SELECT plan(9);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('f1000000-0000-0000-0000-000000000000', 'target@test.local');
SELECT tests.create_supabase_user('f1000000-0000-0000-0000-000000000001', 'viewer@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('f1000000-0000-0000-0000-000000000000', 'T', '1995-01-01', 'female', 900001, 'published'),
  ('f1000000-0000-0000-0000-000000000001', 'V', '1994-01-01', 'male',   900001, 'published');

insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 980000, 'Kalıp soru ' || g, 1, case when g<=3 then 'easy' when g<=6 then 'medium' else 'hard' end
from generate_series(1,7) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 981000, g + 980000, 'A', 1 from generate_series(1,7) g
union all
select g + 982000, g + 980000, 'B', 2 from generate_series(1,7) g;
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select 'f1000000-0000-0000-0000-000000000000', g + 980000, g + 981000,
       case when g<=3 then 'easy' when g<=6 then 'medium' else 'hard' end
from generate_series(1,7) g;
insert into public.taxonomies (id, name, question_body) overriding system value values (980101, 'Meslek', 'Ne iş yapar?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (980101, 980101, 'A'), (980102, 980101, 'B'), (980103, 980101, 'C');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
values (980101,980102),(980102,980101),(980101,980103),(980103,980101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (980201, 'Zor 1', 2, 'hard', 980101), (980202, 'Zor 2', 2, 'hard', 980101);
insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('f1000000-0000-0000-0000-000000000000', 980201, 980101, 'hard'),
  ('f1000000-0000-0000-0000-000000000000', 980202, 980101, 'hard');
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (980299, 'Zor 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (980391, 980299, 'A', 1), (980392, 980299, 'B', 2);
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
values ('f1000000-0000-0000-0000-000000000000', 980299, 980391, 'hard');
insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('f1000000-0000-0000-0000-000000000000', 'height_cm', 170, true);
insert into public.custom_questions (id, profile_id, body)
values ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000000', 'Soru?');
insert into public.custom_options (id, question_id, body, position)
values ('f3000000-0000-0000-0000-000000000001', 'f2000000-0000-0000-0000-000000000001', 'X', 1),
       ('f3000000-0000-0000-0000-000000000002', 'f2000000-0000-0000-0000-000000000001', 'Y', 2);
update public.custom_questions set correct_option_id = 'f3000000-0000-0000-0000-000000000001'
  where id = 'f2000000-0000-0000-0000-000000000001';

create or replace function tests.pick_wrong_np(p_attempt_id uuid, p_position int, p_correct text)
returns text language sql as $$
  select opt ->> 'id'
  from public.attempt_questions aq, jsonb_array_elements(aq.shown_option_ids -> 'options') opt
  where aq.attempt_id = p_attempt_id and aq.position = p_position and (opt ->> 'id') <> p_correct
  limit 1;
$$;

SELECT tests.authenticate_as('f1000000-0000-0000-0000-000000000001');
CREATE TEMP TABLE started_v AS SELECT public.start_quiz('f1000000-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();

create temp table ca (attempt_id uuid, position int, correct_option_id text);
grant select on ca to authenticated;
insert into ca select (payload->>'attempt_id')::uuid, position, correct_option_id
  from started_v, public.attempt_questions where attempt_id = (payload->>'attempt_id')::uuid;

SELECT tests.authenticate_as('f1000000-0000-0000-0000-000000000001');
do $$
declare v_attempt uuid; v_correct text;
begin
  select (payload->>'attempt_id')::uuid into v_attempt from started_v;
  select correct_option_id into v_correct from ca where attempt_id = v_attempt and position = 1;
  perform public.submit_answer(v_attempt, 1, v_correct);
end $$;
SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.notifications
     where user_id = 'f1000000-0000-0000-0000-000000000000' and type = 'quiz_progress'),
  1::bigint,
  '1. cevaptan sonra tek bir quiz_progress bildirimi var'
);

SELECT is(
  (select progress_current from public.notifications
     where user_id = 'f1000000-0000-0000-0000-000000000000' and type = 'quiz_progress' and superseded_by is null),
  1,
  'progress_current = 1 (bastırılmamış tek satır)'
);

SELECT tests.authenticate_as('f1000000-0000-0000-0000-000000000001');
do $$
declare v_attempt uuid; v_correct text;
begin
  select (payload->>'attempt_id')::uuid into v_attempt from started_v;
  select correct_option_id into v_correct from ca where attempt_id = v_attempt and position = 2;
  perform public.submit_answer(v_attempt, 2, v_correct);
end $$;
SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.notifications
     where user_id = 'f1000000-0000-0000-0000-000000000000' and type = 'quiz_progress'),
  2::bigint,
  '2. cevaptan sonra toplamda 2 satır var (eski satır SİLİNMEDİ, bastırıldı)'
);

SELECT is(
  (select count(*) from public.notifications
     where user_id = 'f1000000-0000-0000-0000-000000000000' and type = 'quiz_progress' and superseded_by is null),
  1::bigint,
  'Ama yalnızca 1 tanesi HÂLÂ bastırılmamış (en güncel)'
);

SELECT tests.authenticate_as('f1000000-0000-0000-0000-000000000000');
SELECT is(
  jsonb_array_length(
    jsonb_path_query_array(public.get_my_notifications(30), '$[*] ? (@.type == "quiz_progress")')
  ),
  1,
  'get_my_notifications, bastırılmış quiz_progress satırını göstermiyor (yalnızca en güncel 1 tane)'
);

SELECT is(
  jsonb_path_query_first(public.get_my_notifications(30), '$[*] ? (@.type == "quiz_progress")') ->> 'progress_current',
  '2',
  'get_my_notifications''ta görünen (tek) quiz_progress, en güncel ilerlemeyi (2) taşıyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- Kalan 3 soruyu (3,4,5) doğru cevaplayıp checkpoint'i geçir, sonra
-- 6-10'da tam 4 doğru daha yaparak final skoru 6'da sabitle (near_miss).
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('f1000000-0000-0000-0000-000000000001');
do $$
declare v_attempt uuid; v_pos int; v_correct text;
begin
  select (payload->>'attempt_id')::uuid into v_attempt from started_v;
  for v_pos in 3..10 loop
    select correct_option_id into v_correct from ca where attempt_id = v_attempt and position = v_pos;
    if v_pos <= 6 then
      perform public.submit_answer(v_attempt, v_pos, v_correct);
    else
      perform public.submit_answer(v_attempt, v_pos, tests.pick_wrong_np(v_attempt, v_pos, v_correct));
    end if;
  end loop;
end $$;
SELECT tests.clear_authentication();

SELECT is(
  (select score from public.quiz_attempts where id = (select (payload->>'attempt_id')::uuid from started_v)),
  6,
  'Final skor tam 6 (near_miss senaryosu)'
);

SELECT is(
  (select is_near_miss from public.notifications
     where user_id = 'f1000000-0000-0000-0000-000000000000' and type = 'near_miss'),
  true,
  'near_miss bildirimi is_near_miss=true ile açıldı'
);

SELECT tests.authenticate_as('f1000000-0000-0000-0000-000000000000');
SELECT ok(
  not (public.get_my_notifications(30)::text ilike '%"actor_username": "V"%')
    and not (public.get_my_notifications(30)::text ilike '%v_user%'),
  'near_miss ve quiz_progress bildirimlerinde gönderenin kimliği hiç görünmüyor (anonim)'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
