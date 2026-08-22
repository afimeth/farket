-- Brifing v3, bölüm 9 adım 6: submit_answer / check_checkpoint / finish_quiz
-- testleri.

BEGIN;
SELECT plan(11);

-- ---------------------------------------------------------------------
-- Paylaşılan global soru havuzu: 7 sabit şıklı act1 kalıp (1-7),
-- 2 taksonomi bazlı act2-zor kalıp (100-101). tests.provision_quiz_pool()
-- her hedef profil için bunlara profile_template_answers + 1 custom soru
-- ekler.
-- ---------------------------------------------------------------------
insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

-- NOT: id'ler 930000+ aralığında — production seed migration'ı
-- question_templates/taxonomies/taxonomy_items/template_options'ı 1'den
-- başlayarak dolduruyor, çakışmasın diye.
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 930000, 'Kalıp soru ' || g, 1, 'easy' from generate_series(1, 7) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 931000, g + 930000, 'Şık A', 1 from generate_series(1, 7) g
union all
select g + 932000, g + 930000, 'Şık B', 2 from generate_series(1, 7) g;

insert into public.taxonomies (id, name, question_body) overriding system value
values (930101, 'Meslek', 'Mesleği ne?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (930101, 930101, 'Öğretmen'), (930102, 930101, 'Mühendis'), (930103, 930101, 'Doktor');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id) values (930101, 930102), (930102, 930101), (930101, 930103), (930103, 930101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (930201, 'Zor soru 1', 2, 'hard', 930101), (930202, 'Zor soru 2', 2, 'hard', 930101);

-- Viewer B ve hedefler A (mutlu senaryo), D (checkpoint başarısız),
-- E (sıra/tekrar denemesi), F (erken finish_quiz), G (skor tam 7 sınırı).
-- C: ilişkisiz kullanıcı (sahiplik testi için).
SELECT tests.create_supabase_user('22222222-2222-2222-2222-222222222222', 'b@test.local');
SELECT tests.create_supabase_user('33333333-3333-3333-3333-333333333333', 'c@test.local');
SELECT tests.create_supabase_user('aaaaaaaa-0000-0000-0000-000000000000', 'a@test.local');
SELECT tests.create_supabase_user('dddddddd-0000-0000-0000-000000000000', 'd@test.local');
SELECT tests.create_supabase_user('eeeeeeee-0000-0000-0000-000000000000', 'e@test.local');
SELECT tests.create_supabase_user('ffffffff-0000-0000-0000-000000000000', 'f@test.local');
SELECT tests.create_supabase_user('99999999-0000-0000-0000-000000000000', 'g@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('22222222-2222-2222-2222-222222222222', 'B', '1994-01-01', 'male',   900001, 'published'),
  ('33333333-3333-3333-3333-333333333333', 'C', '1993-01-01', 'male',   900001, 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000000', 'A', '1995-01-01', 'female', 900001, 'published'),
  ('dddddddd-0000-0000-0000-000000000000', 'D', '1995-01-01', 'female', 900001, 'published'),
  ('eeeeeeee-0000-0000-0000-000000000000', 'E', '1995-01-01', 'female', 900001, 'published'),
  ('ffffffff-0000-0000-0000-000000000000', 'F', '1995-01-01', 'female', 900001, 'published'),
  ('99999999-0000-0000-0000-000000000000', 'G', '1995-01-01', 'female', 900001, 'published');

SELECT tests.provision_quiz_pool('aaaaaaaa-0000-0000-0000-000000000000', 'A serbest');
SELECT tests.provision_quiz_pool('dddddddd-0000-0000-0000-000000000000', 'D serbest');
SELECT tests.provision_quiz_pool('eeeeeeee-0000-0000-0000-000000000000', 'E serbest');
SELECT tests.provision_quiz_pool('ffffffff-0000-0000-0000-000000000000', 'F serbest');
SELECT tests.provision_quiz_pool('99999999-0000-0000-0000-000000000000', 'G serbest');

-- correct_answers: her attempt_id + position için doğru cevabı tutan ortak
-- geçici tablo. Yalnızca postgres (owner) doldurabilir; authenticated'a
-- SELECT veriliyor ki submit_answer'a doğru şıkkı geçebilelim (bu bir test
-- yapısı — gerçek istemci bu tabloyu hiç görmez).
create temp table correct_answers (attempt_id uuid, position int, correct_option_id text);
grant select on correct_answers to authenticated;

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 1) Mutlu senaryo: B, A'ya karşı 10 soruyu da doğru cevaplar.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');
CREATE TEMP TABLE started_a AS SELECT public.start_quiz('aaaaaaaa-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();

insert into correct_answers (attempt_id, position, correct_option_id)
  select (payload ->> 'attempt_id')::uuid, position, correct_option_id
  from started_a, public.attempt_questions
  where attempt_id = (payload ->> 'attempt_id')::uuid;

SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');

do $$
declare
  v_attempt uuid;
  v_pos int;
  v_correct text;
begin
  select (payload ->> 'attempt_id')::uuid into v_attempt from started_a;
  for v_pos in 1..10 loop
    select correct_option_id into v_correct from correct_answers where attempt_id = v_attempt and position = v_pos;
    perform public.submit_answer(v_attempt, v_pos, v_correct);
  end loop;
end $$;

SELECT is(
  (select status::text from public.quiz_attempts where id = (select (payload ->> 'attempt_id')::uuid from started_a)),
  'completed',
  'Mutlu senaryo: 10/10 sonunda deneme completed'
);

SELECT is(
  (select unlocked_tier from public.quiz_attempts where id = (select (payload ->> 'attempt_id')::uuid from started_a)),
  10,
  'Mutlu senaryo: skor 10 → kademe 10 (v4.1 ödül merdiveni: 1. denemede tam skor tavana (max_tier=10) kadar çıkar)'
);

SELECT is(
  (select count(*) from public.hidden_profiles
     where viewer_id = '22222222-2222-2222-2222-222222222222'
       and target_profile_id = 'aaaaaaaa-0000-0000-0000-000000000000'),
  0::bigint,
  'Mutlu senaryoda gizleme kaydı açılmaz'
);

-- finish_quiz idempotent: tekrar çağrılınca hata vermeden aynı sonucu döner.
SELECT lives_ok(
  format($$ select public.finish_quiz('%s'::uuid) $$, (select (payload ->> 'attempt_id')::uuid from started_a)),
  'finish_quiz, zaten tamamlanmış bir denemede tekrar çağrılınca hata vermez (idempotent)'
);

-- ---------------------------------------------------------------------
-- 2) Checkpoint başarısız: B, D'ye karşı ilk 5 soruda sadece 2 doğru verir.
-- ---------------------------------------------------------------------
SELECT tests.clear_authentication();
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');
CREATE TEMP TABLE started_d AS SELECT public.start_quiz('dddddddd-0000-0000-0000-000000000000') AS payload;
SELECT tests.clear_authentication();

insert into correct_answers (attempt_id, position, correct_option_id)
  select (payload ->> 'attempt_id')::uuid, position, correct_option_id
  from started_d, public.attempt_questions
  where attempt_id = (payload ->> 'attempt_id')::uuid;

SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');

do $$
declare
  v_attempt uuid;
  v_pos int;
  v_correct text;
begin
  select (payload ->> 'attempt_id')::uuid into v_attempt from started_d;
  -- 1 ve 2. sorularda doğru, 3-4-5'te bilerek yanlış (sabit şıklı
  -- sorularda diğer şık her zaman 'yanlış' sayılır).
  for v_pos in 1..5 loop
    select correct_option_id into v_correct from correct_answers where attempt_id = v_attempt and position = v_pos;
    if v_pos <= 2 then
      perform public.submit_answer(v_attempt, v_pos, v_correct);
    else
      -- Bu havuzdaki her sabit şıklı sorunun iki şıkkı var: doğru olan
      -- (id = template_id+1000, provision_quiz_pool'daki "Şık A") ve
      -- yanlış olan (id = template_id+2000, "Şık B"). Yani "doğru id +
      -- 1000" her zaman geçerli ama yanlış bir şıktır.
      perform public.submit_answer(v_attempt, v_pos, (v_correct::int + 1000)::text);
    end if;
  end loop;
end $$;

SELECT is(
  (select status::text from public.quiz_attempts where id = (select (payload ->> 'attempt_id')::uuid from started_d)),
  'failed_checkpoint',
  'İlk 5 soruda 4''ten az doğru → deneme failed_checkpoint olur'
);

SELECT is(
  (select count(*) from public.hidden_profiles
     where viewer_id = '22222222-2222-2222-2222-222222222222'
       and target_profile_id = 'dddddddd-0000-0000-0000-000000000000'),
  1::bigint,
  'Checkpoint başarısız olunca ikinci şans (hidden_profiles) kaydı açılır (bekleme/bedel detayı v41_second_chance_test.sql''de)'
);

SELECT throws_ok(
  format(
    $$ select public.submit_answer('%s'::uuid, 6, 'x') $$,
    (select (payload ->> 'attempt_id')::uuid from started_d)
  ),
  'Bu deneme artık aktif değil',
  'Checkpoint başarısız olduktan sonra 6. soruya cevap verilemez'
);

-- ---------------------------------------------------------------------
-- 3) Sıra / tekrar kısıtı: B, E'ye karşı sorulara sırayla cevap vermeli.
-- ---------------------------------------------------------------------
SELECT tests.clear_authentication();
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');
CREATE TEMP TABLE started_e AS SELECT public.start_quiz('eeeeeeee-0000-0000-0000-000000000000') AS payload;

SELECT throws_ok(
  format(
    $$ select public.submit_answer('%s'::uuid, 2, 'x') $$,
    (select (payload ->> 'attempt_id')::uuid from started_e)
  ),
  'Sorulara sırayla cevap vermelisin (beklenen pozisyon: 1)',
  '1. soru cevaplanmadan 2. soruya cevap verilemez'
);

SELECT tests.clear_authentication();
insert into correct_answers (attempt_id, position, correct_option_id)
  select (payload ->> 'attempt_id')::uuid, position, correct_option_id
  from started_e, public.attempt_questions
  where attempt_id = (payload ->> 'attempt_id')::uuid;
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');

do $$
declare
  v_attempt uuid;
  v_correct text;
begin
  select (payload ->> 'attempt_id')::uuid into v_attempt from started_e;
  select correct_option_id into v_correct from correct_answers where attempt_id = v_attempt and position = 1;
  perform public.submit_answer(v_attempt, 1, v_correct);
end $$;

SELECT throws_ok(
  format(
    $$ select public.submit_answer('%s'::uuid, 1, 'x') $$,
    (select (payload ->> 'attempt_id')::uuid from started_e)
  ),
  'Sorulara sırayla cevap vermelisin (beklenen pozisyon: 2)',
  'Zaten cevaplanmış bir soru (1) tekrar cevaplanamaz'
);

-- ---------------------------------------------------------------------
-- 4) Sahiplik: C, B'nin denemesine cevap gönderemez.
-- ---------------------------------------------------------------------
SELECT tests.clear_authentication();
SELECT tests.authenticate_as('33333333-3333-3333-3333-333333333333');
SELECT throws_ok(
  format(
    $$ select public.submit_answer('%s'::uuid, 1, 'x') $$,
    (select (payload ->> 'attempt_id')::uuid from started_a)
  ),
  'Bu deneme sana ait değil',
  'C, B''nin denemesine cevap gönderemez'
);

-- ---------------------------------------------------------------------
-- 5) finish_quiz'i erken çağırma.
-- ---------------------------------------------------------------------
SELECT tests.clear_authentication();
SELECT tests.authenticate_as('22222222-2222-2222-2222-222222222222');
CREATE TEMP TABLE started_f AS SELECT public.start_quiz('ffffffff-0000-0000-0000-000000000000') AS payload;

SELECT throws_ok(
  format(
    $$ select public.finish_quiz('%s'::uuid) $$,
    (select (payload ->> 'attempt_id')::uuid from started_f)
  ),
  'Quiz henüz tamamlanmadı (0 / 10 soru cevaplandı)',
  'Hiç soru cevaplanmadan finish_quiz çağrılamaz'
);

SELECT * FROM finish();
ROLLBACK;
