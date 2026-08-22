-- v4.1 Migration 4: ikinci şans (hidden_profiles yeniden yazımı,
-- start_retry, attempt_no farkında start_quiz, soru hariç tutma).
--
-- ÖNEMLİ BULGU (test yazılırken ortaya çıktı, migration'da düzeltilmedi —
-- rapora düşüldü): finish_quiz'in "0-3 doğru → 14 gün / 5 hak" dalı
-- PRATİKTE HİÇ ÇALIŞMIYOR. Checkpoint (5. soru) zaten skor >=4 şartı
-- arıyor ve geçilmezse deneme submit_answer'da 'Bu deneme artık aktif
-- değil' ile 6. sorudan itibaren tamamen durduruluyor (finish_quiz'e HİÇ
-- ulaşılamıyor). Yani finish_quiz'e ulaşan her deneme zaten checkpoint'i
-- geçmiştir (skor >=4), final skor hiçbir zaman 0-3 olamaz. Bu dal kodda
-- var (spesifikasyona harfiyen uyuluyor) ama gerçek akışta ölü kod —
-- aşağıdaki test bunu yalnızca skoru elle 2'ye düşürüp finish_quiz'i
-- doğrudan çağırarak (normal akışın DIŞINDA) doğruluyor.

BEGIN;
SELECT plan(18);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('c1000000-0000-0000-0000-000000000000', 'target@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values ('c1000000-0000-0000-0000-000000000000', 'T', '1995-01-01', 'female', 900001, 'published');

-- Bol miktarda act1 havuzu (8 kolay + 8 orta + 4 zor) — hem 1. hem 2.
-- deneme için (hariç tutmadan sonra bile) fazlasıyla yeterli.
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 950000, 'Kalıp soru ' || g, 1,
       case when g <= 8 then 'easy' when g <= 16 then 'medium' else 'hard' end
from generate_series(1, 20) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 951000, g + 950000, 'Şık A', 1 from generate_series(1, 20) g
union all
select g + 952000, g + 950000, 'Şık B', 2 from generate_series(1, 20) g;
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select 'c1000000-0000-0000-0000-000000000000', g + 950000, g + 951000,
       case when g <= 8 then 'easy' when g <= 16 then 'medium' else 'hard' end
from generate_series(1, 20) g;

-- act2-zor: 4 taksonomi tabanlı soru (1. deneme 2 tanesini kullanır,
-- hariç tutulunca 2. deneme kalan 2'yi kullanır).
insert into public.taxonomies (id, name, question_body) overriding system value
values (950101, 'Meslek', 'Mesleği ne?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (950101, 950101, 'Öğretmen'), (950102, 950101, 'Mühendis'), (950103, 950101, 'Doktor');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
values (950101, 950102), (950102, 950101), (950101, 950103), (950103, 950101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (950201, 'Zor 1', 2, 'hard', 950101), (950202, 'Zor 2', 2, 'hard', 950101),
       (950203, 'Zor 3', 2, 'hard', 950101), (950204, 'Zor 4', 2, 'hard', 950101),
       (950205, 'Zor 5', 2, 'hard', 950101);
insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('c1000000-0000-0000-0000-000000000000', 950201, 950101, 'hard'),
  ('c1000000-0000-0000-0000-000000000000', 950202, 950101, 'hard'),
  ('c1000000-0000-0000-0000-000000000000', 950203, 950101, 'hard'),
  ('c1000000-0000-0000-0000-000000000000', 950204, 950101, 'hard'),
  ('c1000000-0000-0000-0000-000000000000', 950205, 950101, 'hard');

-- 2. deneme (retry), 1. denemede kullanılan künye alanını dışladığı için
-- en az 2 quiz-eligible alan gerekiyor, yoksa start_quiz retry'da "künye
-- bilgisi yok" hatası fırlatır.
-- 1. deneme, mevcut 1-2 eligible alanı bulabildiği kadarını tüketebilir;
-- retry'de (2. deneme) hâlâ en az 1 tanesi kalması için 3 tane ekliyoruz.
insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values
  ('c1000000-0000-0000-0000-000000000000', 'height_cm', 170, true),
  ('c1000000-0000-0000-0000-000000000000', 'weight_kg', 65, true),
  ('c1000000-0000-0000-0000-000000000000', 'age', 27, true);

-- 2 serbest soru (1. deneme birini kullanır, 2. deneme diğerini).
insert into public.custom_questions (id, profile_id, body)
values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000000', 'Serbest 1'),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000000', 'Serbest 2');
insert into public.custom_options (id, question_id, body, position)
values
  ('c3000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'X', 1),
  ('c3000000-0000-0000-0000-000000000002', 'c2000000-0000-0000-0000-000000000001', 'Y', 2),
  ('c3000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-000000000002', 'X', 1),
  ('c3000000-0000-0000-0000-000000000004', 'c2000000-0000-0000-0000-000000000002', 'Y', 2);
update public.custom_questions set correct_option_id = 'c3000000-0000-0000-0000-000000000001' where id = 'c2000000-0000-0000-0000-000000000001';
update public.custom_questions set correct_option_id = 'c3000000-0000-0000-0000-000000000003' where id = 'c2000000-0000-0000-0000-000000000002';

-- ---------------------------------------------------------------------
-- Viewer V1: skor tam 6 → hemen (0 gün) uygun, bedel 2.
-- İlk 5: 4 doğru 1 yanlış (checkpoint geçer, skor 4). Kalan 5: 2 doğru
-- 3 yanlış (final skor 6).
-- ---------------------------------------------------------------------
SELECT tests.create_supabase_user('c4000000-0000-0000-0000-000000000001', 'v1@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values ('c4000000-0000-0000-0000-000000000001', 'V1', '1994-01-01', 'male', 900001, 'published');

create temp table correct_answers (viewer_id uuid, attempt_id uuid, position int, correct_option_id text);
grant select on correct_answers to authenticated;

SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000001');
CREATE TEMP TABLE started_v1 AS SELECT public.start_quiz('c1000000-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();

insert into correct_answers (viewer_id, attempt_id, position, correct_option_id)
  select 'c4000000-0000-0000-0000-000000000001', (payload ->> 'attempt_id')::uuid, position, correct_option_id
  from started_v1, public.attempt_questions
  where attempt_id = (payload ->> 'attempt_id')::uuid;

-- Yanlış cevap için o pozisyonda GERÇEKTEN gösterilen (dolayısıyla FK
-- açısından geçerli), doğrudan farklı bir şıkkı/maddeyi seçen yardımcı
-- fonksiyon — template_stats'ın option_id/item_id FK'sini kırmadan
-- "kesin yanlış" üretmenin tek güvenli yolu bu (hangi soru tipinin
-- geldiğini bilmeye gerek kalmadan).
create or replace function tests.pick_wrong_option(p_attempt_id uuid, p_position int, p_correct text)
returns text language sql as $$
  select opt ->> 'id'
  from public.attempt_questions aq, jsonb_array_elements(aq.shown_option_ids -> 'options') opt
  where aq.attempt_id = p_attempt_id and aq.position = p_position and (opt ->> 'id') <> p_correct
  limit 1;
$$;

SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000001');
do $$
declare
  v_attempt uuid; v_pos int; v_correct text;
begin
  select (payload ->> 'attempt_id')::uuid into v_attempt from started_v1;
  for v_pos in 1..10 loop
    select correct_option_id into v_correct from correct_answers
      where viewer_id = 'c4000000-0000-0000-0000-000000000001' and attempt_id = v_attempt and position = v_pos;
    -- 1-4 ve 6-7 doğru (toplam 6), 5 ve 8-10 yanlış.
    if v_pos in (1,2,3,4,6,7) then
      perform public.submit_answer(v_attempt, v_pos, v_correct);
    else
      perform public.submit_answer(v_attempt, v_pos, tests.pick_wrong_option(v_attempt, v_pos, v_correct));
    end if;
  end loop;
end $$;

SELECT is(
  (select score from public.quiz_attempts where id = (select (payload ->> 'attempt_id')::uuid from started_v1)),
  6,
  'V1: final skor tam 6 (checkpoint''te 4/5 ile geçti, kalanda 2/5 daha doğru)'
);

SELECT tests.clear_authentication();
SELECT is(
  (select retry_cost from public.hidden_profiles
     where viewer_id = 'c4000000-0000-0000-0000-000000000001' and target_profile_id = 'c1000000-0000-0000-0000-000000000000'),
  2,
  'Skor 6 → retry_cost = 2'
);
SELECT ok(
  (select available_at <= now() + interval '1 minute' from public.hidden_profiles
     where viewer_id = 'c4000000-0000-0000-0000-000000000001' and target_profile_id = 'c1000000-0000-0000-0000-000000000000'),
  'Skor 6 → available_at hemen (0 gün bekleme)'
);

-- ---------------------------------------------------------------------
-- start_retry validasyonu (V1 üzerinden).
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000001');

SELECT throws_ok(
  $$ select public.start_retry('99999999-9999-9999-9999-999999999999') $$,
  'Bu profil için bir ikinci şans kaydı yok',
  'İlişkisiz bir profil için start_retry çağrılamaz'
);

-- daily_quotas.quiz_credits_used şu an checkpoint iadesi olmadığı için
-- 1 (start_quiz'in kendi çağrısı). retry_cost=2 ekleyince 3 olacak,
-- bu hâlâ 15''in altında olduğu için başarılı olmalı.
SELECT lives_ok(
  $$ select public.start_retry('c1000000-0000-0000-0000-000000000000') $$,
  'Uygun (available_at geçmiş, yeterli hak) start_retry başarılı'
);

SELECT throws_ok(
  $$ select public.start_retry('c1000000-0000-0000-0000-000000000000') $$,
  'Bu profil için ikinci şansını zaten kullandın',
  'retry_used=true olduktan sonra start_retry tekrar çağrılamaz'
);

-- ---------------------------------------------------------------------
-- start_quiz artık attempt_no=2 olarak açılmalı: max_tier=8, ve
-- 1. denemede sorulan HİÇBİR template/custom soru tekrar gelmemeli.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE started_v1_retry AS SELECT public.start_quiz('c1000000-0000-0000-0000-000000000000') AS payload;

SELECT is(
  (started_v1_retry.payload ->> 'attempt_no')::int, 2,
  '2. deneme attempt_no=2 olarak açıldı'
) FROM started_v1_retry;

SELECT is(
  (started_v1_retry.payload ->> 'max_tier')::int, 8,
  '2. denemede max_tier=8 dönüyor'
) FROM started_v1_retry;

SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.attempt_questions aq1
     join public.attempt_questions aq2
       on aq1.template_id = aq2.template_id and aq1.template_id is not null
     where aq1.attempt_id = (select (payload ->> 'attempt_id')::uuid from started_v1)
       and aq2.attempt_id = (select (payload ->> 'attempt_id')::uuid from started_v1_retry)),
  0::bigint,
  'SORU HARİÇ TUTMA: 2. denemede 1. denemeyle ORTAK HİÇ template_id yok'
);

SELECT is(
  (select count(*) from public.attempt_questions aq1
     join public.attempt_questions aq2
       on aq1.custom_question_id = aq2.custom_question_id and aq1.custom_question_id is not null
     where aq1.attempt_id = (select (payload ->> 'attempt_id')::uuid from started_v1)
       and aq2.attempt_id = (select (payload ->> 'attempt_id')::uuid from started_v1_retry)),
  0::bigint,
  'SORU HARİÇ TUTMA: 2. denemede 1. denemeyle ORTAK serbest soru yok'
);

SELECT is(
  (select max_tier from public.quiz_attempts where id = (select (payload ->> 'attempt_id')::uuid from started_v1_retry)),
  8,
  'quiz_attempts.max_tier=8 kalıcı olarak kaydedildi'
);

SELECT is(
  (select credits_spent from public.quiz_attempts where id = (select (payload ->> 'attempt_id')::uuid from started_v1_retry)),
  2,
  'quiz_attempts.credits_spent = retry_cost (2)'
);

-- İkinci denemede 10/10 yapsa bile unlocked_tier 8'i AŞAMAZ (max_tier).
insert into correct_answers (viewer_id, attempt_id, position, correct_option_id)
  select 'c4000000-0000-0000-0000-000000000001', (payload ->> 'attempt_id')::uuid, position, correct_option_id
  from started_v1_retry, public.attempt_questions
  where attempt_id = (payload ->> 'attempt_id')::uuid;

SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000001');
do $$
declare
  v_attempt uuid; v_pos int; v_correct text;
begin
  select (payload ->> 'attempt_id')::uuid into v_attempt from started_v1_retry;
  for v_pos in 1..10 loop
    select correct_option_id into v_correct from correct_answers
      where viewer_id = 'c4000000-0000-0000-0000-000000000001' and attempt_id = v_attempt and position = v_pos;
    perform public.submit_answer(v_attempt, v_pos, v_correct);
  end loop;
end $$;

SELECT is(
  (select unlocked_tier from public.quiz_attempts where id = (select (payload ->> 'attempt_id')::uuid from started_v1_retry)),
  8,
  'GÜVENLİK: 2. denemede 10/10 yapılsa bile unlocked_tier max_tier (8) ile sınırlı, 9/10''a çıkmıyor'
);

SELECT tests.clear_authentication();

-- Üçüncü deneme: start_quiz kendi mesajıyla reddetmeli (CHECK kısıtına
-- hiç gerek kalmadan, kullanıcı dostu bir hata ile).
SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000001');
SELECT throws_ok(
  $$ select public.start_quiz('c1000000-0000-0000-0000-000000000000') $$,
  'Bu profil için iki deneme hakkını da kullandın',
  'Üçüncü deneme start_quiz''in kendi kontrolüyle (CHECK''e varmadan) reddedilir'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- Checkpoint'te elenme: 0 gün / 0 bedel + hak iadesi.
-- ---------------------------------------------------------------------
SELECT tests.create_supabase_user('c4000000-0000-0000-0000-000000000002', 'v2@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values ('c4000000-0000-0000-0000-000000000002', 'V2', '1994-01-01', 'male', 900001, 'published');

SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000002');
CREATE TEMP TABLE started_v2 AS SELECT public.start_quiz('c1000000-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();

SELECT is(
  (select quiz_credits_used from public.daily_quotas
     where user_id = 'c4000000-0000-0000-0000-000000000002' and date = current_date),
  1,
  'start_quiz sonrası V2''nin günlük kredisi 1''e çıktı'
);

insert into correct_answers (viewer_id, attempt_id, position, correct_option_id)
  select 'c4000000-0000-0000-0000-000000000002', (payload ->> 'attempt_id')::uuid, position, correct_option_id
  from started_v2, public.attempt_questions
  where attempt_id = (payload ->> 'attempt_id')::uuid;

SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000002');
do $$
declare
  v_attempt uuid; v_pos int; v_correct text;
begin
  select (payload ->> 'attempt_id')::uuid into v_attempt from started_v2;
  for v_pos in 1..5 loop
    select correct_option_id into v_correct from correct_answers
      where viewer_id = 'c4000000-0000-0000-0000-000000000002' and attempt_id = v_attempt and position = v_pos;
    if v_pos <= 2 then
      perform public.submit_answer(v_attempt, v_pos, v_correct);
    else
      perform public.submit_answer(v_attempt, v_pos, tests.pick_wrong_option(v_attempt, v_pos, v_correct));
    end if;
  end loop;
end $$;
SELECT tests.clear_authentication();

SELECT is(
  (select retry_cost from public.hidden_profiles
     where viewer_id = 'c4000000-0000-0000-0000-000000000002' and target_profile_id = 'c1000000-0000-0000-0000-000000000000'),
  0,
  'Checkpoint''te elenme → retry_cost = 0'
);

SELECT is(
  (select quiz_credits_used from public.daily_quotas
     where user_id = 'c4000000-0000-0000-0000-000000000002' and date = current_date),
  0,
  'HAK İADESİ: checkpoint''te elenince harcanan kredi geri veriliyor (1 -> 0)'
);

-- ---------------------------------------------------------------------
-- Ölü kod doğrulaması: finish_quiz'in 0-3 dalı (14 gün/5 hak) yalnızca
-- doğal akışın DIŞINDA, skoru elle düşürerek test edilebiliyor —
-- checkpoint bunu normal akışta hiç mümkün kılmıyor (bkz. dosya başı notu).
-- ---------------------------------------------------------------------
SELECT tests.create_supabase_user('c4000000-0000-0000-0000-000000000003', 'v3@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values ('c4000000-0000-0000-0000-000000000003', 'V3', '1994-01-01', 'male', 900001, 'published');

SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000003');
CREATE TEMP TABLE started_v3 AS SELECT public.start_quiz('c1000000-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();

insert into correct_answers (viewer_id, attempt_id, position, correct_option_id)
  select 'c4000000-0000-0000-0000-000000000003', (payload ->> 'attempt_id')::uuid, position, correct_option_id
  from started_v3, public.attempt_questions
  where attempt_id = (payload ->> 'attempt_id')::uuid;

SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000003');
do $$
declare
  v_attempt uuid; v_pos int; v_correct text;
begin
  select (payload ->> 'attempt_id')::uuid into v_attempt from started_v3;
  for v_pos in 1..10 loop
    select correct_option_id into v_correct from correct_answers
      where viewer_id = 'c4000000-0000-0000-0000-000000000003' and attempt_id = v_attempt and position = v_pos;
    perform public.submit_answer(v_attempt, v_pos, v_correct);
  end loop;
end $$;
SELECT tests.clear_authentication();

-- Doğal akışta skor 10 oldu (unlocked_tier=10, hiç hidden_profiles kaydı
-- yok). Elle skoru 2'ye düşürüp finish_quiz'i "yeniden tetiklemek" için
-- status'u in_progress'e geri alıyoruz (yalnızca bu ölü-kod testi için,
-- gerçek bir kullanıcı asla bu duruma düşemez).
update public.quiz_attempts
  set score = 2, status = 'in_progress', unlocked_tier = 0, completed_at = null
  where id = (select (payload ->> 'attempt_id')::uuid from started_v3);

SELECT tests.authenticate_as('c4000000-0000-0000-0000-000000000003');
SELECT public.finish_quiz((select (payload ->> 'attempt_id')::uuid from started_v3));
SELECT tests.clear_authentication();

SELECT is(
  (select retry_cost from public.hidden_profiles
     where viewer_id = 'c4000000-0000-0000-0000-000000000003' and target_profile_id = 'c1000000-0000-0000-0000-000000000000'),
  5,
  '(Ölü kod, elle tetiklendi) skor 0-3 → retry_cost = 5'
);

SELECT * FROM finish();
ROLLBACK;
