-- Görev 5 (v3): günlük kotaların sınırına ulaşınca gerçekten RPC'yi
-- durdurduğu doğrulanıyor. v4.1 Migration 5'te sabit 200/15 limitleri
-- kalktı (deck_profiles_served + get_quiz_allowance ile değişti) —
-- testler buna göre güncellendi (quiz_attempts_used -> quiz_credits_used,
-- discover_calls_used=200 -> deck_profiles_served=daily_deck_limit).

BEGIN;
SELECT plan(6);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('55550000-0000-0000-0000-000000000000', 'viewer@test.local');
SELECT tests.create_supabase_user('55550000-0000-0000-0000-000000000001', 'target1@test.local');
SELECT tests.create_supabase_user('55550000-0000-0000-0000-000000000002', 'target2@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values
  ('55550000-0000-0000-0000-000000000000', 'V', '1994-01-01', 'male',   900001, 'v_user', 'published'),
  ('55550000-0000-0000-0000-000000000001', 'T1', '1995-01-01', 'female', 900001, 't1_user', 'published'),
  ('55550000-0000-0000-0000-000000000002', 'T2', '1995-01-01', 'female', 900001, 't2_user', 'published');

-- ---------------------------------------------------------------------
-- 1) discover_profiles: günlük deste sınırı (app_settings.daily_deck_limit,
-- varsayılan 25) doldurulmuş -> bir sonraki çağrı hata.
-- ---------------------------------------------------------------------
insert into public.daily_quotas (user_id, date, deck_profiles_served)
values ('55550000-0000-0000-0000-000000000000', current_date,
        (select value::int from public.app_settings where key = 'daily_deck_limit'));

SELECT tests.authenticate_as('55550000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.discover_profiles(20) $$,
  'Günlük deste sınırına ulaştın',
  'discover_profiles, günlük deste limiti dolunca reddediyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 2) start_quiz: günlük hak (get_quiz_allowance) doldurulmuş -> yeni bir
-- hedefe bile deneme açılamıyor. Bu taze test kullanıcısı için hesaplanan
-- hak 4'tür (taban 3 + bekleyen mesaj isteği yok +1; doğrulanmamış,
-- quiz geçmişi yok, profil eksik olduğu için diğer bonuslar yok) — bunu
-- doğrudan quiz_allowance/quiz_credits_used olarak yazıp start_quiz'in
-- ONU HESAPLAMADAN (zaten dolu olduğu için) kullandığını doğruluyoruz.
-- ---------------------------------------------------------------------
insert into public.daily_quotas (user_id, date, quiz_allowance, quiz_credits_used)
values ('55550000-0000-0000-0000-000000000000', current_date, 4, 4)
on conflict (user_id, date) do update set quiz_allowance = 4, quiz_credits_used = 4;

SELECT tests.authenticate_as('55550000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.start_quiz('55550000-0000-0000-0000-000000000001') $$,
  'Günlük quiz deneme kotan doldu',
  'start_quiz, günlük hak (quiz_allowance) doldurulunca yeni bir hedefte bile reddediyor'
);
SELECT tests.clear_authentication();

SELECT is(
  (select count(*) from public.quiz_attempts
     where viewer_id = '55550000-0000-0000-0000-000000000000'
       and target_profile_id = '55550000-0000-0000-0000-000000000001'),
  0::bigint,
  'Kota hatası veren start_quiz çağrısı hiçbir attempt satırı bırakmıyor (tüm fonksiyon geri sarılıyor)'
);

-- ---------------------------------------------------------------------
-- 3) send_message: günlük 10 mesaj isteği doldurulmuş -> yeni bir alıcıya
-- (V'nin zaten 8/10 skorla künyesini açtığı T2'ye) ilk mesaj isteği bile
-- reddediliyor; yarım kalan conversation/message de rollback ile silinmiş
-- oluyor (fonksiyonun kendisi tek bir exception ile abort oluyor).
-- ---------------------------------------------------------------------
insert into public.quiz_attempts (viewer_id, target_profile_id, status, score, unlocked_tier)
values ('55550000-0000-0000-0000-000000000000', '55550000-0000-0000-0000-000000000002', 'completed', 8, 8);

update public.daily_quotas set message_requests_used = 10
  where user_id = '55550000-0000-0000-0000-000000000000' and date = current_date;

SELECT tests.authenticate_as('55550000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.send_message('55550000-0000-0000-0000-000000000002', 'Merhaba!') $$,
  'Günlük mesaj isteği kotan doldu',
  'send_message, 10 istek doldurulunca (mesaj göndermeye hakkı olsa bile) 11. istekte reddediyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 4) send_message (kabul edilmiş konuşma dalı): günlük 300 mesaj doldurulmuş
-- -> zaten kabul edilmiş bir konuşmada bile yeni mesaj reddediliyor.
-- ---------------------------------------------------------------------
insert into public.conversations (participant_a, participant_b, status, expires_at, unlocked_tier)
values ('55550000-0000-0000-0000-000000000000', '55550000-0000-0000-0000-000000000002', 'accepted', now() + interval '7 days', 8);

update public.daily_quotas set messages_sent_used = 300
  where user_id = '55550000-0000-0000-0000-000000000000' and date = current_date;

SELECT tests.authenticate_as('55550000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.send_message('55550000-0000-0000-0000-000000000002', 'Selam tekrar!') $$,
  'Günlük mesaj gönderme kotan doldu, yarın tekrar dene',
  'send_message, kabul edilmiş konuşmada 300 mesaj doldurulunca 301. mesajı reddediyor'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 5) reports: 24 saatte 20 şikayet doldurulmuş -> 21. şikayet reddediliyor.
-- ---------------------------------------------------------------------
insert into public.reports (reporter_id, reported_profile_id, reason, created_at)
select '55550000-0000-0000-0000-000000000000', '55550000-0000-0000-0000-000000000001', 'spam', now()
from generate_series(1, 20);

SELECT tests.authenticate_as('55550000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ insert into public.reports (reporter_id, reported_profile_id, reason)
     values ('55550000-0000-0000-0000-000000000000', '55550000-0000-0000-0000-000000000001', 'spam') $$,
  'Bugün çok fazla şikayet gönderdin, yarın tekrar dene',
  'reports, 24 saatte 20 şikayet doldurulunca 21.yi reddediyor'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
