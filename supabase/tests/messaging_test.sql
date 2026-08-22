-- Mesajlaşma testleri: kademeye göre karakter sınırı, tek mesaj kuralı,
-- kabul/red akışı, engelleme tetikleyicisi.

BEGIN;
SELECT plan(14);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('11111111-0000-0000-0000-000000000000', 'a@test.local');
SELECT tests.create_supabase_user('22222222-0000-0000-0000-000000000000', 'b@test.local');
SELECT tests.create_supabase_user('33333333-0000-0000-0000-000000000000', 't@test.local');
SELECT tests.create_supabase_user('44444444-0000-0000-0000-000000000000', 't2@test.local');
SELECT tests.create_supabase_user('55555555-0000-0000-0000-000000000000', 'd@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('11111111-0000-0000-0000-000000000000', 'A', '1994-01-01', 'male', 900001, 'published'),
  ('22222222-0000-0000-0000-000000000000', 'B', '1994-01-01', 'male', 900001, 'published'),
  ('33333333-0000-0000-0000-000000000000', 'T', '1995-01-01', 'female', 900001, 'published'),
  ('44444444-0000-0000-0000-000000000000', 'T2', '1995-01-01', 'female', 900001, 'published'),
  ('55555555-0000-0000-0000-000000000000', 'D', '1994-01-01', 'male', 900001, 'published');

-- A: T'ye karşı 7, T2'ye karşı 7. B: T'ye karşı 8. D: hiç denemesi yok.
insert into public.quiz_attempts (viewer_id, target_profile_id, status, score, unlocked_tier)
values
  ('11111111-0000-0000-0000-000000000000', '33333333-0000-0000-0000-000000000000', 'completed', 7, 7),
  ('11111111-0000-0000-0000-000000000000', '44444444-0000-0000-0000-000000000000', 'completed', 7, 7),
  ('22222222-0000-0000-0000-000000000000', '33333333-0000-0000-0000-000000000000', 'completed', 8, 8);

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 1) Tamamlanmış/başarılı denemesi olmayan (D), mesaj isteği gönderemez.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('55555555-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.send_message('33333333-0000-0000-0000-000000000000', 'merhaba') $$,
  'Bu kişiye mesaj isteği gönderme hakkın yok (en az 7 doğru cevap gerekiyor)',
  'Skoru yetersiz (denemesi yok) kullanıcı mesaj isteği gönderemez'
);

-- ---------------------------------------------------------------------
-- 2) A (skor 7), T'ye 50 karakter sınırıyla ilk mesajı gönderir.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
CREATE TEMP TABLE sent_a_t AS SELECT public.send_message('33333333-0000-0000-0000-000000000000', repeat('x', 50)) AS payload;

SELECT is(
  (select payload ->> 'status' from sent_a_t),
  'pending',
  'İlk mesajdan sonra konuşma pending durumunda'
);

SELECT is(
  (select char_limit_applied from public.messages
     where conversation_id = (select (payload ->> 'conversation_id')::uuid from sent_a_t)),
  50,
  'Skor 7 için karakter sınırı 50 olarak kaydedilir'
);

-- ---------------------------------------------------------------------
-- 3) Aynı skorla (A → T2), 51 karakterlik ilk mesaj reddedilir.
-- ---------------------------------------------------------------------
SELECT throws_ok(
  format($$ select public.send_message('44444444-0000-0000-0000-000000000000', '%s') $$, repeat('x', 51)),
  'İlk mesaj en fazla 50 karakter olabilir',
  '51 karakterlik ilk mesaj (50 sınırıyla) reddedilir'
);

-- ---------------------------------------------------------------------
-- 4) A, T'ye bekleyen isteği varken ikinci bir mesaj gönderemez.
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ select public.send_message('33333333-0000-0000-0000-000000000000', 'ikinci mesaj') $$,
  'Zaten bekleyen bir mesaj isteğin var, karşı taraf kabul etmeden yeni mesaj gönderemezsin',
  'A, T''ye bekleyen isteği varken ikinci mesaj gönderemez'
);

-- ---------------------------------------------------------------------
-- 5) T (alıcı), kabul etmeden send_message ile direkt cevap veremez.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.send_message('11111111-0000-0000-0000-000000000000', 'selam') $$,
  'Önce mesaj isteğini kabul etmelisin',
  'Alıcı, isteği kabul etmeden mesaj gönderemez'
);

-- ---------------------------------------------------------------------
-- 6) Gönderen kendi isteğini kabul edemez.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
SELECT throws_ok(
  format($$ select public.accept_conversation('%s'::uuid) $$, (select (payload ->> 'conversation_id')::uuid from sent_a_t)),
  'Kendi gönderdiğin mesaj isteğini kabul edemezsin',
  'A, kendi gönderdiği isteği kabul edemez'
);

-- ---------------------------------------------------------------------
-- 7) T kabul eder → konuşma accepted olur, karakter sınırı kalkar.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');
SELECT lives_ok(
  format($$ select public.accept_conversation('%s'::uuid) $$, (select (payload ->> 'conversation_id')::uuid from sent_a_t)),
  'T, A''nın isteğini kabul edebilir'
);

SELECT is(
  (select status::text from public.conversations
     where id = (select (payload ->> 'conversation_id')::uuid from sent_a_t)),
  'accepted',
  'Kabul sonrası konuşma accepted durumunda'
);

SELECT lives_ok(
  format($$ select public.send_message('11111111-0000-0000-0000-000000000000', '%s') $$, repeat('y', 300)),
  'Kabul sonrası 300 karakterlik bir mesaj bile sınıra takılmadan gönderilebilir'
);

-- ---------------------------------------------------------------------
-- 8) B (skor 8) → T: istek gönderir, T reddeder, sonrası kapalı kalır.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
CREATE TEMP TABLE sent_b_t AS SELECT public.send_message('33333333-0000-0000-0000-000000000000', repeat('z', 100)) AS payload;

SELECT is(
  (select char_limit_applied from public.messages
     where conversation_id = (select (payload ->> 'conversation_id')::uuid from sent_b_t)),
  100,
  'Skor 8 için karakter sınırı 100 olarak kaydedilir'
);

SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');
SELECT public.decline_conversation((select (payload ->> 'conversation_id')::uuid from sent_b_t));
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.send_message('33333333-0000-0000-0000-000000000000', 'tekrar dener') $$,
  'Bu konuşma kapalı',
  'Reddedilen konuşmaya yeni mesaj isteği gönderilemez'
);

-- ---------------------------------------------------------------------
-- 9) Engelleme, açık (accepted) bir konuşmayı otomatik kapatır (trigger).
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');
SELECT tests.clear_authentication();

insert into public.blocks (blocker_id, blocked_id)
values ('33333333-0000-0000-0000-000000000000', '11111111-0000-0000-0000-000000000000');

SELECT is(
  (select status::text from public.conversations
     where id = (select (payload ->> 'conversation_id')::uuid from sent_a_t)),
  'blocked',
  'T, A''yı engelleyince aralarındaki accepted konuşma otomatik blocked olur'
);

SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.send_message('33333333-0000-0000-0000-000000000000', 'merhaba') $$,
  'Bu kullanıcıyla mesajlaşma engellenmiş',
  'Engellenmiş bir kullanıcıya yeni mesaj isteği gönderilemez'
);

SELECT * FROM finish();
ROLLBACK;
