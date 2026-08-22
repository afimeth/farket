-- v4.1 sonraki fazlar, Faz 1: ödül merdiveni (8=foto referansı,
-- 9=soru alanı+gizli kart, 10=mühür+ters künye açılması).

BEGIN;
SELECT plan(16);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('e1000000-0000-0000-0000-000000000000', 'target@test.local');
SELECT tests.create_supabase_user('e1000000-0000-0000-0000-000000000001', 'v7@test.local');
SELECT tests.create_supabase_user('e1000000-0000-0000-0000-000000000002', 'v9@test.local');
SELECT tests.create_supabase_user('e1000000-0000-0000-0000-000000000003', 'v10@test.local');
SELECT tests.create_supabase_user('e1000000-0000-0000-0000-000000000004', 'stranger@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('e1000000-0000-0000-0000-000000000000', 'T',  '1995-01-01', 'female', 900001, 'published'),
  ('e1000000-0000-0000-0000-000000000001', 'V7', '1994-01-01', 'male',   900001, 'published'),
  ('e1000000-0000-0000-0000-000000000002', 'V9', '1994-01-01', 'male',   900001, 'published'),
  ('e1000000-0000-0000-0000-000000000003', 'V10','1994-01-01', 'male',   900001, 'published'),
  ('e1000000-0000-0000-0000-000000000004', 'STR','1994-01-01', 'male',   900001, 'published');

insert into public.identity_card (profile_id, show_name, show_age)
values
  ('e1000000-0000-0000-0000-000000000000', true, true),
  ('e1000000-0000-0000-0000-000000000003', true, false);

insert into public.photos (id, profile_id, position, storage_path_thumb, storage_path_full, moderation_status)
values ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000000', 1,
        'e1/1_thumb.webp', 'e1/1_full.webp', 'approved');

-- ---------------------------------------------------------------------
-- set_secret_card
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000000');

SELECT throws_ok(
  $$ select public.set_secret_card('photo', null, null) $$,
  'Fotoğraf türünde gizli kart için photo_id gerekli',
  'photo türünde photo_id zorunlu'
);

SELECT throws_ok(
  $$ select public.set_secret_card('song', null, null) $$,
  'Not/şarkı türünde gizli kart için metin gerekli',
  'note/song türünde metin zorunlu'
);

SELECT lives_ok(
  $$ select public.set_secret_card('note', null, 'En sevdiğim anım...') $$,
  'Geçerli bir not tipi gizli kart ayarlanabilir'
);

SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000004');
SELECT throws_ok(
  $$ select public.set_secret_card('photo', 'e2000000-0000-0000-0000-000000000001'::uuid, null) $$,
  'Seçilen fotoğraf sana ait değil',
  'Başkasının fotoğrafı gizli kart olarak ayarlanamaz'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- Soru altyapısı: T için 7 act1 + 2 act2-zor + 1 serbest soru.
-- ---------------------------------------------------------------------
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 970000, 'Kalıp soru ' || g, 1, case when g<=3 then 'easy' when g<=6 then 'medium' else 'hard' end
from generate_series(1,7) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 971000, g + 970000, 'A', 1 from generate_series(1,7) g
union all
select g + 972000, g + 970000, 'B', 2 from generate_series(1,7) g;
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select 'e1000000-0000-0000-0000-000000000000', g + 970000, g + 971000,
       case when g<=3 then 'easy' when g<=6 then 'medium' else 'hard' end
from generate_series(1,7) g;
insert into public.taxonomies (id, name, question_body) overriding system value values (970101, 'Meslek', 'Ne iş yapar?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (970101, 970101, 'A'), (970102, 970101, 'B'), (970103, 970101, 'C');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
values (970101,970102),(970102,970101),(970101,970103),(970103,970101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (970201, 'Zor 1', 2, 'hard', 970101), (970202, 'Zor 2', 2, 'hard', 970101);
insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('e1000000-0000-0000-0000-000000000000', 970201, 970101, 'hard'),
  ('e1000000-0000-0000-0000-000000000000', 970202, 970101, 'hard');
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (970299, 'Zor 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (970391, 970299, 'A', 1), (970392, 970299, 'B', 2);
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
values ('e1000000-0000-0000-0000-000000000000', 970299, 970391, 'hard');
insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('e1000000-0000-0000-0000-000000000000', 'height_cm', 170, true);
insert into public.custom_questions (id, profile_id, body)
values ('e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000000', 'Soru?');
insert into public.custom_options (id, question_id, body, position)
values ('e4000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'X', 1),
       ('e4000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000001', 'Y', 2);
update public.custom_questions set correct_option_id = 'e4000000-0000-0000-0000-000000000001'
  where id = 'e3000000-0000-0000-0000-000000000001';

create or replace function tests.pick_wrong_rl(p_attempt_id uuid, p_position int, p_correct text)
returns text language sql as $$
  select opt ->> 'id'
  from public.attempt_questions aq, jsonb_array_elements(aq.shown_option_ids -> 'options') opt
  where aq.attempt_id = p_attempt_id and aq.position = p_position and (opt ->> 'id') <> p_correct
  limit 1;
$$;

create temp table ca (viewer_id uuid, attempt_id uuid, position int, correct_option_id text);
grant select on ca to authenticated;
create temp table att (viewer_id uuid, attempt_id uuid);
grant select on att to authenticated;

-- V7: skor tam 7 (ilk 5 doğru -> checkpoint geçer, 6-7 doğru, 8-10 yanlış).
SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000001');
CREATE TEMP TABLE started_v7 AS SELECT public.start_quiz('e1000000-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();
insert into att select 'e1000000-0000-0000-0000-000000000001', (payload->>'attempt_id')::uuid from started_v7;
insert into ca (viewer_id, attempt_id, position, correct_option_id)
  select 'e1000000-0000-0000-0000-000000000001', (payload->>'attempt_id')::uuid, position, correct_option_id
  from started_v7, public.attempt_questions where attempt_id = (payload->>'attempt_id')::uuid;

SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000001');
do $$
declare v_attempt uuid; v_pos int; v_correct text;
begin
  select attempt_id into v_attempt from att where viewer_id = 'e1000000-0000-0000-0000-000000000001';
  for v_pos in 1..10 loop
    select correct_option_id into v_correct from ca where viewer_id = 'e1000000-0000-0000-0000-000000000001' and attempt_id = v_attempt and position = v_pos;
    if v_pos <= 7 then
      perform public.submit_answer(v_attempt, v_pos, v_correct);
    else
      perform public.submit_answer(v_attempt, v_pos, tests.pick_wrong_rl(v_attempt, v_pos, v_correct));
    end if;
  end loop;
end $$;
SELECT tests.clear_authentication();

-- V9: skor tam 9 (yalnızca 10. soru yanlış).
SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000002');
CREATE TEMP TABLE started_v9 AS SELECT public.start_quiz('e1000000-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();
insert into att select 'e1000000-0000-0000-0000-000000000002', (payload->>'attempt_id')::uuid from started_v9;
insert into ca (viewer_id, attempt_id, position, correct_option_id)
  select 'e1000000-0000-0000-0000-000000000002', (payload->>'attempt_id')::uuid, position, correct_option_id
  from started_v9, public.attempt_questions where attempt_id = (payload->>'attempt_id')::uuid;

SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000002');
do $$
declare v_attempt uuid; v_pos int; v_correct text;
begin
  select attempt_id into v_attempt from att where viewer_id = 'e1000000-0000-0000-0000-000000000002';
  for v_pos in 1..10 loop
    select correct_option_id into v_correct from ca where viewer_id = 'e1000000-0000-0000-0000-000000000002' and attempt_id = v_attempt and position = v_pos;
    if v_pos <= 9 then
      perform public.submit_answer(v_attempt, v_pos, v_correct);
    else
      perform public.submit_answer(v_attempt, v_pos, tests.pick_wrong_rl(v_attempt, v_pos, v_correct));
    end if;
  end loop;
end $$;
SELECT tests.clear_authentication();

-- V10: skor tam 10 (hepsi doğru).
SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000003');
CREATE TEMP TABLE started_v10 AS SELECT public.start_quiz('e1000000-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();
insert into att select 'e1000000-0000-0000-0000-000000000003', (payload->>'attempt_id')::uuid from started_v10;
insert into ca (viewer_id, attempt_id, position, correct_option_id)
  select 'e1000000-0000-0000-0000-000000000003', (payload->>'attempt_id')::uuid, position, correct_option_id
  from started_v10, public.attempt_questions where attempt_id = (payload->>'attempt_id')::uuid;

SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000003');
do $$
declare v_attempt uuid; v_pos int; v_correct text;
begin
  select attempt_id into v_attempt from att where viewer_id = 'e1000000-0000-0000-0000-000000000003';
  for v_pos in 1..10 loop
    select correct_option_id into v_correct from ca where viewer_id = 'e1000000-0000-0000-0000-000000000003' and attempt_id = v_attempt and position = v_pos;
    perform public.submit_answer(v_attempt, v_pos, v_correct);
  end loop;
end $$;
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- V7 (tier 7): foto referansı ve soru alanı reddedilir, gizli kart kapalı.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000001');

SELECT throws_ok(
  format($$ select public.send_message('e1000000-0000-0000-0000-000000000000', 'Merhaba', '%s'::uuid, null) $$,
    'e2000000-0000-0000-0000-000000000001'),
  'Fotoğraf referansı göndermek için en az 8 doğru cevap gerekiyor',
  'V7 (tier 7), foto referansı gönderemez'
);

SELECT throws_ok(
  $$ select public.send_message('e1000000-0000-0000-0000-000000000000', 'Merhaba', null, 'Bu ne demek?') $$,
  'Soru sormak için en az 9 doğru cevap gerekiyor',
  'V7 (tier 7), soru soramaz'
);

SELECT throws_ok(
  format($$ select public.get_secret_card('%s'::uuid) $$, (select attempt_id from att where viewer_id = 'e1000000-0000-0000-0000-000000000001')),
  'Gizli kart yalnızca ilk denemede en az 9 doğru cevapla açılır',
  'V7 (skor 7 < 9), gizli kartı göremez'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- V9 (tier 9): foto referansı + soru alanı + gizli kart hepsi açık.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000002');

SELECT throws_ok(
  $$ select public.send_message('e1000000-0000-0000-0000-000000000000', 'Merhaba', '99999999-9999-9999-9999-999999999999'::uuid, null) $$,
  'Geçersiz fotoğraf referansı',
  'V9, T''ye ait olmayan bir fotoğrafı referans gösteremez'
);

SELECT lives_ok(
  format($$ select public.send_message('e1000000-0000-0000-0000-000000000000', 'Merhaba', '%s'::uuid, 'En sevdiğin renk?') $$,
    'e2000000-0000-0000-0000-000000000001'),
  'V9 (tier 9), geçerli foto referansı + soru alanıyla mesaj gönderebilir'
);

SELECT is(
  (select public.get_secret_card((select attempt_id from att where viewer_id = 'e1000000-0000-0000-0000-000000000002'))) ->> 'type',
  'note',
  'V9 (skor 9), T''nin gizli kartını (note) görebilir'
);
SELECT tests.clear_authentication();

SELECT is(
  (select referenced_photo_id from public.messages
     where conversation_id = (select id from public.conversations
       where participant_a = 'e1000000-0000-0000-0000-000000000002' and participant_b = 'e1000000-0000-0000-0000-000000000000')),
  'e2000000-0000-0000-0000-000000000001'::uuid,
  'V9''nun mesajında referenced_photo_id doğru kaydedilmiş'
);

-- ---------------------------------------------------------------------
-- V10 (tier 10): mühür + ters yönlü künye açılması.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000003');
SELECT public.send_message('e1000000-0000-0000-0000-000000000000', 'Merhaba!');
SELECT tests.clear_authentication();

-- Konuşma id'sini postgres olarak (RLS'i atlayarak) bir kez sabitliyoruz —
-- ilişkisiz kullanıcının auth context'inde bu satır RLS'ten görünmez
-- olacağı için ileride tekrar sorgulanamaz.
create temp table v10_conv as
  select id from public.conversations
  where participant_a = 'e1000000-0000-0000-0000-000000000003' and participant_b = 'e1000000-0000-0000-0000-000000000000';
grant select on v10_conv to authenticated;

SELECT is(
  (select has_seal from public.conversations
     where participant_a = 'e1000000-0000-0000-0000-000000000003' and participant_b = 'e1000000-0000-0000-0000-000000000000'),
  true,
  'V10 (tier 10), konuşma mühürlü (has_seal=true) açılıyor'
);

SELECT is(
  (select count(*) from public.identity_reveals
     where viewer_id = 'e1000000-0000-0000-0000-000000000000' and target_profile_id = 'e1000000-0000-0000-0000-000000000003'),
  1::bigint,
  'Ters yönlü identity_reveals kaydı açıldı (T, V10''u quiz çözmeden görebilecek)'
);

SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000000');
SELECT is(
  public.get_sender_identity((select id from public.conversations
    where participant_a = 'e1000000-0000-0000-0000-000000000003' and participant_b = 'e1000000-0000-0000-0000-000000000000')),
  '{"name": "V10"}'::jsonb,
  'T (alıcı), get_sender_identity ile V10''un (show_name=true, show_age=false) künyesini görebiliyor'
);
SELECT tests.clear_authentication();

SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000004');
SELECT throws_ok(
  format($$ select public.get_sender_identity('%s'::uuid) $$, (select id::text from v10_conv)),
  'Bu konuşma sana ait değil',
  'İlişkisiz biri get_sender_identity çağıramaz'
);
SELECT tests.clear_authentication();

SELECT tests.authenticate_as('e1000000-0000-0000-0000-000000000003');
SELECT throws_ok(
  format($$ select public.get_sender_identity('%s'::uuid) $$, (select id::text from v10_conv)),
  'Bu konuşma sana ait değil',
  'Gönderenin kendisi (alıcı değil) get_sender_identity çağıramaz'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
