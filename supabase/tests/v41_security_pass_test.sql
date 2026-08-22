-- v4.1 sonraki fazlar, Faz 6: v4.1 §8 güvenlik checklist'inin toplu
-- doğrulama geçişi. Daha önceki fazlarda zaten testlenmiş maddeler
-- (3. deneme, ikinci denemede 9/10'a çıkma, soru hariç tutma, deste
-- sınırı, daily_quotas yazma, 8/9. kademe alanları, tek şikayet) burada
-- TEKRAR edilmiyor — yalnızca bu geçişte bulunan 4 gerçek boşluk:
--   1) available_at gelmeden start_retry
--   2) yetersiz hakla start_retry
--   3) başkasının secret_card_text'ini doğrudan okuma
--   4) süresi dolmuş (expires_at) konuşmaya mesaj gönderme — GERÇEK BUG,
--      bu migration'da send_message'a expires_at kontrolü eklenerek
--      düzeltildi (bkz. 20260818121047_v41_security_pass.sql).

BEGIN;
SELECT plan(4);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('66600000-0000-0000-0000-000000000000', 'v@test.local');
SELECT tests.create_supabase_user('66600000-0000-0000-0000-000000000001', 't1@test.local');
SELECT tests.create_supabase_user('66600000-0000-0000-0000-000000000002', 't2@test.local');
SELECT tests.create_supabase_user('66600000-0000-0000-0000-000000000003', 'owner@test.local');
SELECT tests.create_supabase_user('66600000-0000-0000-0000-000000000004', 'stranger@test.local');
SELECT tests.create_supabase_user('66600000-0000-0000-0000-000000000005', 'sender@test.local');
SELECT tests.create_supabase_user('66600000-0000-0000-0000-000000000006', 'recipient@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('66600000-0000-0000-0000-000000000000', 'V',  '1994-01-01', 'male', 900001, 'published'),
  ('66600000-0000-0000-0000-000000000001', 'T1', '1994-01-01', 'male', 900001, 'published'),
  ('66600000-0000-0000-0000-000000000002', 'T2', '1994-01-01', 'male', 900001, 'published'),
  ('66600000-0000-0000-0000-000000000003', 'OWN','1994-01-01', 'male', 900001, 'published'),
  ('66600000-0000-0000-0000-000000000004', 'STR','1994-01-01', 'male', 900001, 'published'),
  ('66600000-0000-0000-0000-000000000005', 'SND','1994-01-01', 'male', 900001, 'published'),
  ('66600000-0000-0000-0000-000000000006', 'RCV','1994-01-01', 'male', 900001, 'published');

-- ---------------------------------------------------------------------
-- 1) available_at gelmeden start_retry.
-- ---------------------------------------------------------------------
insert into public.hidden_profiles (viewer_id, target_profile_id, first_attempt_score, available_at, retry_cost, retry_used)
values ('66600000-0000-0000-0000-000000000000', '66600000-0000-0000-0000-000000000001', 4, now() + interval '3 days', 3, false);

SELECT tests.authenticate_as('66600000-0000-0000-0000-000000000000');
SELECT throws_matching(
  $$ select public.start_retry('66600000-0000-0000-0000-000000000001') $$,
  'Henüz tekrar deneyemezsin',
  'available_at gelmeden start_retry reddedilir'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 2) Yetersiz hakla start_retry.
-- ---------------------------------------------------------------------
insert into public.hidden_profiles (viewer_id, target_profile_id, first_attempt_score, available_at, retry_cost, retry_used)
values ('66600000-0000-0000-0000-000000000000', '66600000-0000-0000-0000-000000000002', 5, now() - interval '1 hour', 5, false);
insert into public.daily_quotas (user_id, date, quiz_allowance, quiz_credits_used)
values ('66600000-0000-0000-0000-000000000000', current_date, 4, 4)
on conflict (user_id, date) do update set quiz_allowance = 4, quiz_credits_used = 4;

SELECT tests.authenticate_as('66600000-0000-0000-0000-000000000000');
SELECT throws_matching(
  $$ select public.start_retry('66600000-0000-0000-0000-000000000002') $$,
  'Günlük quiz hakkın ikinci deneme için yetersiz',
  'Yetersiz hakla (4 kullanılmış/4 hak, 5 bedel gerekiyor) start_retry reddedilir'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 3) Başkasının secret_card_text'ini doğrudan okuma.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('66600000-0000-0000-0000-000000000003');
SELECT public.set_secret_card('note', null, 'gizli sır');
SELECT tests.clear_authentication();

SELECT tests.authenticate_as('66600000-0000-0000-0000-000000000004');
SELECT is(
  (select count(*) from public.profiles
     where id = '66600000-0000-0000-0000-000000000003' and secret_card_text is not null),
  0::bigint,
  'Başkası (STR), OWN''ın secret_card_text''ini doğrudan sorgulayamaz (RLS satırı tamamen gizler)'
);
SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 4) Süresi dolmuş (expires_at) konuşmaya mesaj gönder — bu geçişte
-- bulunup düzeltilen gerçek boşluk.
-- ---------------------------------------------------------------------
insert into public.conversations (id, participant_a, participant_b, status, expires_at)
values ('66700000-0000-0000-0000-000000000001', '66600000-0000-0000-0000-000000000005',
        '66600000-0000-0000-0000-000000000006', 'pending', now() - interval '1 minute');
insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
values ('66700000-0000-0000-0000-000000000001', '66600000-0000-0000-0000-000000000005', 'Merhaba', 50);

SELECT tests.authenticate_as('66600000-0000-0000-0000-000000000006');
SELECT throws_ok(
  $$ select public.send_message('66600000-0000-0000-0000-000000000005', 'Kabul!') $$,
  'Bu mesaj isteğinin süresi doldu',
  'Alıcı, süresi dolmuş (expires_at geçmiş, status hâlâ pending — cron henüz çalışmamış) bir isteğe mesaj gönderemez'
);
SELECT tests.clear_authentication();

SELECT * FROM finish();
ROLLBACK;
