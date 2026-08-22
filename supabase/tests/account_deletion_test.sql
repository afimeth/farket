-- delete_account / restore_account / export_my_data / purge_deleted_accounts
-- testleri.

BEGIN;
SELECT plan(12);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir');

SELECT tests.create_supabase_user('11111111-0000-0000-0000-000000000000', 'a@test.local');
SELECT tests.create_supabase_user('22222222-0000-0000-0000-000000000000', 'b@test.local');
SELECT tests.create_supabase_user('33333333-0000-0000-0000-000000000000', 'c@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, username, status)
values
  ('11111111-0000-0000-0000-000000000000', 'A', '1994-01-01', 'male', 900001, 'a_user', 'published'),
  ('22222222-0000-0000-0000-000000000000', 'B', '1994-01-01', 'male', 900001, 'b_user', 'published'),
  ('33333333-0000-0000-0000-000000000000', 'C', '1994-01-01', 'male', 900001, 'c_user', 'published');

insert into public.photos (profile_id, position, storage_path_thumb, storage_path_full, moderation_status)
values ('11111111-0000-0000-0000-000000000000', 1, 'private/a/1_thumb.webp', 'private/a/1_full.webp', 'approved');

insert into public.conversations (id, participant_a, participant_b, status)
values ('99999999-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000000',
        '22222222-0000-0000-0000-000000000000', 'accepted');

insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
values ('99999999-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000000', 'merhaba', null);

-- C'nin de bir mesajı olsun — purge sonrası bu mesajın SİLİNMEDİĞİNİ
-- doğrulamak için (karşı tarafın konuşma geçmişi korunmalı).
insert into public.conversations (id, participant_a, participant_b, status)
values ('99999999-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000000',
        '22222222-0000-0000-0000-000000000000', 'accepted');
insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
values ('99999999-0000-0000-0000-000000000002', '33333333-0000-0000-0000-000000000000', 'selam', null);

SELECT tests.clear_authentication();

-- ---------------------------------------------------------------------
-- 1) delete_account: yumuşak silme + açık konuşma kapanır.
-- ---------------------------------------------------------------------
SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
SELECT public.delete_account();
SELECT tests.clear_authentication();

SELECT is(
  (select status::text from public.profiles where id = '11111111-0000-0000-0000-000000000000'),
  'deleted',
  'delete_account sonrası profil status=deleted'
);

SELECT ok(
  (select deleted_at from public.profiles where id = '11111111-0000-0000-0000-000000000000') is not null,
  'deleted_at zaman damgası yazıldı'
);

SELECT is(
  (select status::text from public.conversations where id = '99999999-0000-0000-0000-000000000001'),
  'closed',
  'Açık (accepted) konuşma delete_account ile closed olur'
);

SELECT tests.authenticate_as('11111111-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.delete_account() $$,
  'Profil bulunamadı ya da zaten silinmiş',
  'Zaten silinmiş bir hesap tekrar silinemez'
);

-- ---------------------------------------------------------------------
-- 2) restore_account: 30 gün içinde geri alınabilir.
-- ---------------------------------------------------------------------
SELECT lives_ok(
  $$ select public.restore_account() $$,
  '30 gün içinde restore_account başarılı olur'
);

SELECT is(
  (select status::text from public.profiles where id = '11111111-0000-0000-0000-000000000000'),
  'published',
  'restore_account sonrası profil tekrar published'
);

SELECT tests.clear_authentication();
SELECT tests.authenticate_as('22222222-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.restore_account() $$,
  'Hesap silinmiş durumda değil',
  'Silinmemiş bir hesapta restore_account çağrılamaz'
);

-- 30 günü geçmiş bir silme simülasyonu.
SELECT tests.clear_authentication();
update public.profiles set status = 'deleted', deleted_at = now() - interval '31 days'
  where id = '33333333-0000-0000-0000-000000000000';
SELECT tests.authenticate_as('33333333-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.restore_account() $$,
  'Geri alma süresi (30 gün) dolmuş',
  '30 günü geçmiş bir silme geri alınamaz'
);

-- ---------------------------------------------------------------------
-- 3) purge_deleted_accounts: authenticated'a hiç açık değil.
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ select public.purge_deleted_accounts() $$,
  'permission denied for function purge_deleted_accounts',
  'purge_deleted_accounts, authenticated rolünden çağrılamaz'
);

-- ---------------------------------------------------------------------
-- 4) purge_deleted_accounts (service context): anonimleştirir, mesajları
--    SİLMEZ.
-- ---------------------------------------------------------------------
SELECT tests.clear_authentication();
SELECT is(
  (public.purge_deleted_accounts()->>'purged_count')::int,
  1,
  'purge_deleted_accounts, 30 günü geçmiş tam olarak 1 hesabı işler (C)'
);

SELECT is(
  (select display_name from public.profiles where id = '33333333-0000-0000-0000-000000000000'),
  '[silinmiş kullanıcı]',
  'Purge sonrası display_name anonimleştirildi'
);

SELECT is(
  (select count(*) from public.messages where conversation_id = '99999999-0000-0000-0000-000000000002'),
  1::bigint,
  'Purge, karşı tarafın konuşmasındaki mesajı silmiyor (korunuyor)'
);

SELECT * FROM finish();
ROLLBACK;
