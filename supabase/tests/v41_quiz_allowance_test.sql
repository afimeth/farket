-- v4.1 Migration 5: hak sistemi (get_quiz_allowance, deck_profiles_served).

BEGIN;
SELECT plan(10);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('d1000000-0000-0000-0000-000000000000', 'u1@test.local');
SELECT tests.create_supabase_user('d1000000-0000-0000-0000-000000000001', 'u2@test.local');
SELECT tests.create_supabase_user('d1000000-0000-0000-0000-000000000002', 'other@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values
  ('d1000000-0000-0000-0000-000000000000', 'U1', '1994-01-01', 'male', 900001, 'u1_user', 'published'),
  ('d1000000-0000-0000-0000-000000000001', 'U2', '1994-01-01', 'male', 900001, 'u2_user', 'published'),
  ('d1000000-0000-0000-0000-000000000002', 'O', '1994-01-01', 'male', 900001, 'o_user', 'published');

-- ---------------------------------------------------------------------
-- get_quiz_allowance: taze bir kullanıcı için taban(3) + bekleyen mesaj
-- isteği yok(+1) = 4 (doğrulanmamış, quiz geçmişi yok, profil eksik).
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('d1000000-0000-0000-0000-000000000000');
SELECT is(
  public.get_quiz_allowance('d1000000-0000-0000-0000-000000000000'),
  4,
  'Taze kullanıcı: taban 3 + bekleyen istek yok +1 = 4'
);

SELECT throws_ok(
  $$ select public.get_quiz_allowance('d1000000-0000-0000-0000-000000000001') $$,
  'Yalnızca kendi hakkını sorgulayabilirsin',
  'Başkasının hakkı sorgulanamaz'
);
SELECT tests.clear_authentication();

-- verified_at dolunca +1.
update public.profiles set verified_at = now() where id = 'd1000000-0000-0000-0000-000000000000';
SELECT tests.authenticate_as('d1000000-0000-0000-0000-000000000000');
SELECT is(
  public.get_quiz_allowance('d1000000-0000-0000-0000-000000000000'),
  5,
  'verified_at dolunca hak 4->5'
);
SELECT tests.clear_authentication();

-- Bekleyen (cevaplanmamış) bir mesaj isteği varken +1 verilmiyor.
insert into public.conversations (participant_a, participant_b, status)
values ('d1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000000', 'pending');

SELECT tests.authenticate_as('d1000000-0000-0000-0000-000000000000');
SELECT is(
  public.get_quiz_allowance('d1000000-0000-0000-0000-000000000000'),
  4,
  'Bekleyen mesaj isteği varken hak 5->4 (o bonus verilmiyor)'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- daily_quotas.quiz_allowance / deck_profiles_served istemciden yazılamaz
-- (tablo hâlâ yalnızca SELECT — bkz. grants.sql, yeni kolonlar için ayrı
-- bir GRANT açılmadı).
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('d1000000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ update public.daily_quotas set quiz_allowance = 99 where user_id = 'd1000000-0000-0000-0000-000000000000' $$,
  'permission denied for table daily_quotas',
  'quiz_allowance istemciden doğrudan yazılamaz'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- discover_profiles: deste sınırı, kalan kadar döner ve gerçek dönen
-- sayı kadar deck_profiles_served artırır (istenen p_limit değil).
-- ---------------------------------------------------------------------
insert into public.daily_quotas (user_id, date, deck_profiles_served)
values ('d1000000-0000-0000-0000-000000000001', current_date, 23)
on conflict (user_id, date) do update set deck_profiles_served = 23;

-- Şehirde U1 dışında yalnızca U1'in kendisi keşfedilebilir aday: en az
-- 1 onaylı kapak fotoğrafı olan yayınlanmış profil lazım, henüz yok —
-- ekleyelim (U2'nin kendisi hariç, keşfedecek: yalnızca U1 ve O).
insert into public.photos (profile_id, position, storage_path_thumb, storage_path_full, moderation_status)
values
  ('d1000000-0000-0000-0000-000000000000', 1, 'd1/1_thumb.webp', 'd1/1_full.webp', 'approved'),
  ('d1000000-0000-0000-0000-000000000002', 1, 'd2/1_thumb.webp', 'd2/1_full.webp', 'approved');

SELECT tests.authenticate_as('d1000000-0000-0000-0000-000000000001');
SELECT is(
  jsonb_array_length(public.discover_profiles(20)),
  2,
  'deck_profiles_served=23, limit 25 iken 20 istense bile kalan 2 ile sınırlanıyor (2 aday olduğu için 2 döner)'
);

SELECT is(
  (select deck_profiles_served from public.daily_quotas
     where user_id = 'd1000000-0000-0000-0000-000000000001' and date = current_date),
  25,
  'deck_profiles_served, GERÇEK dönen profil sayısı (2) kadar arttı: 23 -> 25'
);

SELECT throws_ok(
  $$ select public.discover_profiles(20) $$,
  'Günlük deste sınırına ulaştın',
  'Deste sınırı (25) dolunca bir sonraki çağrı reddediliyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- start_quiz: quiz_allowance gün içinde BİR KEZ hesaplanıp saklanıyor —
-- koşul (verified_at) sonradan değişse bile aynı gün içinde sabit kalıyor.
-- ---------------------------------------------------------------------
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
select g + 960000, 'Kalıp soru ' || g, 1, case when g<=3 then 'easy' when g<=6 then 'medium' else 'hard' end
from generate_series(1,7) g;
insert into public.template_options (id, template_id, body, position) overriding system value
select g + 961000, g + 960000, 'A', 1 from generate_series(1,7) g
union all
select g + 962000, g + 960000, 'B', 2 from generate_series(1,7) g;
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select 'd1000000-0000-0000-0000-000000000002', g + 960000, g + 961000,
       case when g<=3 then 'easy' when g<=6 then 'medium' else 'hard' end
from generate_series(1,7) g;
insert into public.taxonomies (id, name, question_body) overriding system value values (960101, 'Meslek', 'Ne iş yapar?');
insert into public.taxonomy_items (id, taxonomy_id, label) overriding system value
values (960101, 960101, 'A'), (960102, 960101, 'B'), (960103, 960101, 'C');
insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
values (960101,960102),(960102,960101),(960101,960103),(960103,960101);
insert into public.question_templates (id, body, act, default_difficulty, taxonomy_id) overriding system value
values (960201, 'Zor 1', 2, 'hard', 960101), (960202, 'Zor 2', 2, 'hard', 960101);
insert into public.profile_template_answers (profile_id, template_id, selected_item_id, difficulty)
values
  ('d1000000-0000-0000-0000-000000000002', 960201, 960101, 'hard'),
  ('d1000000-0000-0000-0000-000000000002', 960202, 960101, 'hard');
insert into public.question_templates (id, body, act, default_difficulty) overriding system value
values (960299, 'Zor 3', 2, 'hard');
insert into public.template_options (id, template_id, body, position) overriding system value
values (960391, 960299, 'A', 1), (960392, 960299, 'B', 2);
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
values ('d1000000-0000-0000-0000-000000000002', 960299, 960391, 'hard');
insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_quiz_eligible)
values ('d1000000-0000-0000-0000-000000000002', 'height_cm', 170, true);
insert into public.custom_questions (id, profile_id, body)
values ('d3000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'Soru?');
insert into public.custom_options (id, question_id, body, position)
values ('d3000000-0000-0000-0000-000000000002', 'd3000000-0000-0000-0000-000000000001', 'X', 1),
       ('d3000000-0000-0000-0000-000000000003', 'd3000000-0000-0000-0000-000000000001', 'Y', 2);
update public.custom_questions set correct_option_id = 'd3000000-0000-0000-0000-000000000002'
  where id = 'd3000000-0000-0000-0000-000000000001';

SELECT tests.authenticate_as('d1000000-0000-0000-0000-000000000000');
SELECT public.start_quiz('d1000000-0000-0000-0000-000000000002');
SELECT tests.clear_authentication();

-- Bu noktada U1'in hâlâ cevaplanmamış bir bekleyen isteği var (O'nun
-- gönderdiği), bu yüzden hak taban(3)+verified(+1)+bekleyen-yok(+0) = 4.
SELECT is(
  (select quiz_allowance from public.daily_quotas
     where user_id = 'd1000000-0000-0000-0000-000000000000' and date = current_date),
  4,
  'start_quiz çağrısı quiz_allowance''ı (bu kullanıcı için 4) o gün için sabitledi'
);

-- Koşulları değiştir (verified_at'i kaldır) — quiz_allowance ZATEN dolu
-- olduğu için değişmemeli.
update public.profiles set verified_at = null where id = 'd1000000-0000-0000-0000-000000000000';

SELECT tests.authenticate_as('d1000000-0000-0000-0000-000000000000');
SELECT is(
  (select quiz_allowance from public.daily_quotas
     where user_id = 'd1000000-0000-0000-0000-000000000000' and date = current_date),
  4,
  'Aynı gün içinde koşul değişse bile saklanan quiz_allowance yeniden hesaplanmıyor'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
