-- Farket v4.1 — Migration 2/5: additive kolonlar.
-- profiles/conversations/messages'a yeni alanlar, notifications'ın type
-- CHECK listesine yeni tipler, yeni tablo verification_requests.
--
-- conversations/messages'a eklenen yeni sütunlar için ayrıca bir GRANT
-- gerekmiyor: bu iki tablo zaten yalnızca SELECT ile açık (authenticated),
-- tüm yazma RPC'ler (send_message, accept_conversation vb.) üzerinden ve
-- onlar SECURITY DEFINER olduğu için RLS/GRANT'ı zaten atlıyor.
--
-- profiles İÇİN DURUM FARKLI: profiles'ta authenticated'a blanket
-- `update` grant'ı var (sütun kısıtı yok) — bu yeni eklenen
-- verified_at/tier/secret_card_* sütunları İÇİN GÜVENLİK AÇISINDAN KRİTİK:
-- verified_at yalnızca "elle onaylanacak" (v4.1 §3), tier v1'de hep 'free'
-- olmalı — bunlar client'a açık kalırsa kullanıcı kendini "doğrulanmış"
-- ya da "premium" işaretleyebilir. Bu yüzden profiles.update grant'ı
-- BLANKET'TEN SÜTUN BAZLI'YA düşürüldü, yeni 5 sütun listeye YOK.
-- (Not: city_changed_at/deleted_at/photo_verified_at/phone_verified_at da
-- aynı sınıf bir risk taşıyor ama v4.1 kapsamı dışında — bkz. rapor.)

-- =========================================================================
-- 1) profiles — eklenecek.
-- =========================================================================
alter table public.profiles
  add column verified_at         timestamptz,
  add column tier                text not null default 'free'
                                    check (tier in ('free', 'premium', 'premium_plus')),
  add column secret_card_type    text check (secret_card_type in ('photo', 'note', 'song')),
  add column secret_card_photo_id uuid references public.photos (id) on delete set null,
  add column secret_card_text    text;

revoke update on public.profiles from authenticated;
grant update (
  display_name, birth_date, sex, city_id, district_id, status, age_attested_at, username
) on public.profiles to authenticated;

-- =========================================================================
-- 2) conversations / messages — eklenecek.
-- =========================================================================
alter table public.conversations
  add column expires_at   timestamptz,
  add column has_seal     boolean not null default false,
  add column unlocked_tier int;

alter table public.messages
  add column referenced_photo_id uuid references public.photos (id) on delete set null,
  add column asked_question     text check (char_length(asked_question) <= 100);

-- =========================================================================
-- 3) notifications — type CHECK listesine yeni tipler eklendi.
-- =========================================================================
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'quiz_started', 'identity_revealed', 'quiz_passed', 'perfect_score',
    'message_request', 'request_accepted',
    'quiz_progress', 'near_miss', 'request_expired', 'weekly_digest'
  ));

-- =========================================================================
-- 4) Yeni tablo: verification_requests. v1'de elle onaylanacak (Studio
-- üzerinden) — authenticated'a hiç GRANT yok, bir SECURITY DEFINER RPC
-- (request_verification, sonraki bir fazda eklenecek) üzerinden yazılacak.
-- =========================================================================
create table public.verification_requests (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references public.profiles (id) on delete cascade,
  selfie_path   text not null,
  status        text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);

alter table public.verification_requests enable row level security;
-- Bilerek hiçbir policy/GRANT yok — yazma da okuma da yalnızca ileride
-- eklenecek SECURITY DEFINER fonksiyon(lar) ve service role üzerinden.
