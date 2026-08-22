-- v4.1 sonraki fazlar, Faz 3: expire_pending_conversations + release_stale_hides.

BEGIN;
SELECT plan(8);

insert into public.cities (id, name) overriding system value values (900001, 'Test Şehir'), (900002, 'Boş Şehir');

SELECT tests.create_supabase_user('11100000-0000-0000-0000-000000000000', 'sender@test.local');
SELECT tests.create_supabase_user('11100000-0000-0000-0000-000000000001', 'recipient@test.local');
SELECT tests.create_supabase_user('11100000-0000-0000-0000-000000000002', 'sender2@test.local');
SELECT tests.create_supabase_user('11100000-0000-0000-0000-000000000003', 'recipient2@test.local');

insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('11100000-0000-0000-0000-000000000000', 'S',  '1994-01-01', 'male', 900001, 'published'),
  ('11100000-0000-0000-0000-000000000001', 'R',  '1994-01-01', 'male', 900001, 'published'),
  ('11100000-0000-0000-0000-000000000002', 'S2', '1994-01-01', 'male', 900001, 'published'),
  ('11100000-0000-0000-0000-000000000003', 'R2', '1994-01-01', 'male', 900001, 'published');

-- ---------------------------------------------------------------------
-- expire_pending_conversations
-- ---------------------------------------------------------------------
insert into public.conversations (id, participant_a, participant_b, status, expires_at)
values
  ('22200000-0000-0000-0000-000000000001', '11100000-0000-0000-0000-000000000000',
   '11100000-0000-0000-0000-000000000001', 'pending', now() - interval '1 hour'),
  ('22200000-0000-0000-0000-000000000002', '11100000-0000-0000-0000-000000000002',
   '11100000-0000-0000-0000-000000000003', 'pending', now() + interval '6 days');

SELECT tests.authenticate_as('11100000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.expire_pending_conversations() $$,
  'permission denied for function expire_pending_conversations',
  'authenticated bu fonksiyonu doğrudan çağıramaz'
);
SELECT tests.clear_authentication();

SELECT is(
  public.expire_pending_conversations(),
  1,
  'Süresi dolmuş TEK konuşma işlendi (1 döndü)'
);

SELECT is(
  (select status::text from public.conversations where id = '22200000-0000-0000-0000-000000000001'),
  'expired',
  'Süresi dolan konuşma expired oldu'
);

SELECT is(
  (select status::text from public.conversations where id = '22200000-0000-0000-0000-000000000002'),
  'pending',
  'Süresi dolmayan konuşma pending kalmaya devam ediyor'
);

SELECT is(
  (select count(*) from public.notifications
     where user_id = '11100000-0000-0000-0000-000000000000' and type = 'request_expired'),
  1::bigint,
  'Gönderene (participant_a) request_expired bildirimi gitti'
);

-- ---------------------------------------------------------------------
-- release_stale_hides: viewer V'nin şehrinde HİÇ keşfedilebilir profil
-- yok (Boş Şehir), 3 gizleme kaydı var -> hepsi (deficit çok büyük
-- olduğu için) erken serbest bırakılmalı.
-- ---------------------------------------------------------------------
SELECT tests.create_supabase_user('33300000-0000-0000-0000-000000000000', 'lonely@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values ('33300000-0000-0000-0000-000000000000', 'L', '1994-01-01', 'male', 900002, 'published');

SELECT tests.create_supabase_user('33300000-0000-0000-0000-000000000001', 'h1@test.local');
SELECT tests.create_supabase_user('33300000-0000-0000-0000-000000000002', 'h2@test.local');
SELECT tests.create_supabase_user('33300000-0000-0000-0000-000000000003', 'h3@test.local');
insert into public.profiles (id, display_name, birth_date, sex, city_id, status)
values
  ('33300000-0000-0000-0000-000000000001', 'H1', '1994-01-01', 'male', 900001, 'published'),
  ('33300000-0000-0000-0000-000000000002', 'H2', '1994-01-01', 'male', 900001, 'published'),
  ('33300000-0000-0000-0000-000000000003', 'H3', '1994-01-01', 'male', 900001, 'published');

insert into public.hidden_profiles (viewer_id, target_profile_id, first_attempt_score, available_at, retry_cost, retry_used)
values
  ('33300000-0000-0000-0000-000000000000', '33300000-0000-0000-0000-000000000001', 3, now() + interval '10 days', 5, false),
  ('33300000-0000-0000-0000-000000000000', '33300000-0000-0000-0000-000000000002', 5, now() + interval '2 days', 3, false),
  ('33300000-0000-0000-0000-000000000000', '33300000-0000-0000-0000-000000000003', 5, now() + interval '3 days', 3, false);

SELECT tests.authenticate_as('33300000-0000-0000-0000-000000000000');
SELECT throws_ok(
  $$ select public.release_stale_hides() $$,
  'permission denied for function release_stale_hides',
  'authenticated bu fonksiyonu doğrudan çağıramaz'
);
SELECT tests.clear_authentication();

SELECT public.release_stale_hides();

SELECT is(
  (select count(*) from public.hidden_profiles
     where viewer_id = '33300000-0000-0000-0000-000000000000' and released_early = true and available_at <= now()),
  3::bigint,
  'Boş şehirde (0 görünür profil) 3 gizlemenin de HEPSİ erken serbest bırakıldı'
);

SELECT is(
  (select bool_and(retry_used = false) from public.hidden_profiles
     where viewer_id = '33300000-0000-0000-0000-000000000000'),
  true,
  'Erken serbest bırakma retry_used''ı DEĞİŞTİRMEZ — yalnızca available_at''ı öne çeker (ikinci deneme hâlâ start_retry gerektirir)'
);

SELECT * FROM finish();
ROLLBACK;
