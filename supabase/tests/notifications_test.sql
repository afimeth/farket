-- Görev 3: notifications tablosu ve entegrasyonu testleri.

BEGIN;
SELECT plan(11);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 930000, 'Kalıp soru ' || g, 1, 'easy' from generate_series(1, 7) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 931000, g + 930000, 'Şık A', 1 from generate_series(1, 7) g
union all
select g + 932000, g + 930000, 'Şık B', 2 from generate_series(1, 7) g;
insert into public.taxonomies (id, name, question_body) overriding system value values (930101, 'Meslek', 'Mesleği ne?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (930101, 930101, 'Öğretmen'), (930102, 930101, 'Mühendis'), (930103, 930101, 'Doktor');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id) values (930101, 930102), (930102, 930101), (930101, 930103), (930103, 930101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (930201, 'Zor soru 1', 2, 'hard', 930101), (930202, 'Zor soru 2', 2, 'hard', 930101);

SELECT tests.create_supabase_user('11111111-0000-0000-0000-000000000000', 'a@test.local');
SELECT tests.create_supabase_user('22222222-0000-0000-0000-000000000000', 'b@test.local');
SELECT tests.create_supabase_user('33333333-0000-0000-0000-000000000000', 'c@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values
  ('11111111-0000-0000-0000-000000000000', 'A', '1995-01-01', 'female', 900001, 'a_user', 'published'),
  ('22222222-0000-0000-0000-000000000000', 'B', '1994-01-01', 'male',   900001, 'b_user', 'published'),
  ('33333333-0000-0000-0000-000000000000', 'C', '1993-01-01', 'male',   900001, 'c_user', 'published');

insert into public.identity_card (profile_id, show_name) values ('11111111-0000-0000-0000-000000000000', true);

SELECT tests.provision_quiz_pool('11111111-0000-0000-0000-000000000000', 'A serbest');

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 1) notifications: authenticated'a hiç doğrudan erişim yok.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select count(*) from public.notifications $$,
  'permission denied for table notifications',
  'notifications tablosuna authenticated rolünden doğrudan erişilemez'
);

-- ---------------------------------------------------------------------
-- 2) start_quiz: quiz_started bildirimi + günlük gruplama.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
CREATE TEMP TABLE started_b AS SELECT public.start_quiz('11111111-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();

SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');
SELECT public.start_quiz('11111111-0000-0000-0000-000000000000');
SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.notifications where user_id = '11111111-0000-0000-0000-000000000000' and type = 'quiz_started'),
  1::bigint,
  'İki ayrı viewer aynı gün quiz başlatınca TEK satıra gruplanıyor'
);

SELECT is(
  (select (payload ->> 'count')::int from public.notifications
     where user_id = '11111111-0000-0000-0000-000000000000' and type = 'quiz_started'),
  2,
  'Gruplanan bildirimin payload.count''ı 2''ye çıkmış'
);

SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
SELECT ok(
  not (public.get_my_notifications(30)::text ilike '%b_user%')
  and not (public.get_my_notifications(30)::text ilike '%c_user%'),
  'quiz_started bildiriminde actor_username hiç görünmüyor (anonim)'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 3) B, A'yı tam puanla (10/10) çözer: checkpoint, reveal_identity,
-- quiz_passed/perfect_score entegrasyonu tek akışta doğrulanır.
-- (B'nin denemesi zaten adım 2'de start_quiz ile açıldı; started_b'yi
-- yeniden kullanıyoruz.)
-- ---------------------------------------------------------------------
create temp table correct_answers (attempt_id uuid, position int, correct_option_id text);
grant select on correct_answers to authenticated;
insert into correct_answers (attempt_id, position, correct_option_id)
  select (payload ->> 'attempt_id')::uuid, position, correct_option_id
  from started_b, public.attempt_questions
  where attempt_id = (payload ->> 'attempt_id')::uuid;

SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
do $$
declare
  v_attempt uuid;
  v_pos int;
  v_correct text;
begin
  select (payload ->> 'attempt_id')::uuid into v_attempt from started_b;
  for v_pos in 1..10 loop
    select correct_option_id into v_correct from correct_answers where attempt_id = v_attempt and position = v_pos;
    perform public.submit_answer(v_attempt, v_pos, v_correct);
  end loop;
  perform public.reveal_identity(v_attempt);
end $$;
SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.notifications
     where user_id = '11111111-0000-0000-0000-000000000000' and type = 'identity_revealed'),
  1::bigint,
  'reveal_identity, identity_revealed bildirimi yazdı'
);

SELECT is(
  (select count(*) from public.notifications
     where user_id = '11111111-0000-0000-0000-000000000000' and type = 'perfect_score'),
  1::bigint,
  '10/10 skorla finish_quiz, perfect_score bildirimi yazdı (quiz_passed değil)'
);

-- ---------------------------------------------------------------------
-- 4) send_message: message_request bildirimi, kimlik AÇIK.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
CREATE TEMP TABLE sent AS SELECT public.send_message('11111111-0000-0000-0000-000000000000', 'Merhaba!') AS payload;
SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.notifications
     where user_id = '11111111-0000-0000-0000-000000000000' and type = 'message_request'),
  1::bigint,
  'send_message, message_request bildirimi yazdı'
);

SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
SELECT ok(
  public.get_my_notifications(30)::text ilike '%b_user%',
  'message_request bildiriminde actor_username (b_user) görünüyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 5) accept_conversation: request_accepted bildirimi, kimlik AÇIK.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
SELECT public.accept_conversation((select (payload ->> 'conversation_id')::uuid from sent));
SELECT tests.clear_authentication();

SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
SELECT ok(
  public.get_my_notifications(30)::text ilike '%a_user%',
  'accept_conversation, B''ye request_accepted bildirimi (actor: a_user) gönderdi'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 6) mark_notification_read: yalnızca kendi bildirimini işaretleyebilir.
-- notifications'a authenticated'ın hiç GRANT'ı olmadığı için id'leri
-- postgres (owner) context'inden önceden bir geçici tabloya alıyoruz.
-- ---------------------------------------------------------------------
create temp table notif_ids as
select
  (select id from public.notifications where user_id = '22222222-0000-0000-0000-000000000000' and type = 'request_accepted') as b_request_accepted,
  (select id from public.notifications where user_id = '11111111-0000-0000-0000-000000000000' and type = 'perfect_score') as a_perfect_score;
grant select on notif_ids to authenticated;

SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
SELECT public.mark_notification_read((select b_request_accepted from notif_ids));
SELECT tests.clear_authentication();

SELECT is(
  (select read_at is not null from public.notifications
     where user_id = '22222222-0000-0000-0000-000000000000' and type = 'request_accepted'),
  true,
  'mark_notification_read, kendi bildirimini okunmuş işaretler'
);

SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');
SELECT public.mark_notification_read((select a_perfect_score from notif_ids));
SELECT tests.clear_authentication();

SELECT is(
  (select read_at is not null from public.notifications
     where user_id = '11111111-0000-0000-0000-000000000000' and type = 'perfect_score'),
  false,
  'C, A''nın bildirimini okunmuş işaretleyemez (sessizce 0 satır etkiler)'
);

SELECT * FROM finish();
ROLLBACK;
