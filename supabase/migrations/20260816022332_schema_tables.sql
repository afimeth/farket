-- Farket: temel şema (v3)
-- Brifing v3 esas alınmıştır. v2'deki PostGIS/yarıçap ve YZ soru üretimi
-- kaldırıldı; şehir bazlı keşif ve kalıp/taksonomi soru sistemi eklendi.

-- =========================================================================
-- cities / districts — kapalı referans listeleri
-- =========================================================================
create table public.cities (
  id          int generated always as identity primary key,
  name        text not null unique,
  is_active   boolean not null default true
);

create table public.districts (
  id          int generated always as identity primary key,
  city_id     int not null references public.cities (id) on delete cascade,
  name        text not null,
  is_active   boolean not null default true,
  unique (city_id, name)
);

-- =========================================================================
-- profiles
-- =========================================================================
create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  display_name        text not null check (char_length(display_name) between 1 and 60),
  birth_date          date not null,
  sex                 text not null,
  mode                text not null default 'friendship' check (mode = 'friendship'),
  city_id             int not null references public.cities (id),
  -- v1'de kullanılmıyor; İstanbul için ilçe bazlı filtre ileride eklenecek.
  district_id         int references public.districts (id),
  -- Son şehir değişiminin zaman damgası; 24 saatlik gecikme kuralı bunu okur.
  city_changed_at     timestamptz,
  status              text not null default 'draft'
                        check (status in ('draft', 'published', 'suspended', 'deleted')),
  photo_verified_at   timestamptz,
  phone_verified_at   timestamptz,
  -- Doğrulama değil, beyan kaydı (brifing bölüm 2.3 / v3 profiles notu).
  age_attested_at     timestamptz,
  created_at          timestamptz not null default now(),
  deleted_at          timestamptz
);

comment on column public.profiles.age_attested_at is
  'Kullanıcının 18+ beyanı. Bu bir kimlik doğrulaması DEĞİLDİR, sadece beyan zaman damgasıdır.';

-- =========================================================================
-- identity_card — değişmedi
-- =========================================================================
create table public.identity_card (
  profile_id      uuid primary key references public.profiles (id) on delete cascade,
  show_name       boolean not null default false,
  show_age        boolean not null default false,
  show_occupation boolean not null default false,
  show_city       boolean not null default false,
  show_intent     boolean not null default false,
  -- Genel meslek adı. İş yeri adı, okul adı, semt, sosyal medya alanı YOK.
  occupation      text check (char_length(occupation) <= 60),
  intent          text check (intent in ('arkadaslik', 'aktivite_arkadasi'))
);

-- =========================================================================
-- photos
-- Min 5, maks 7 fotoğraf kuralı satır-sayısı kısıtı olduğu için burada
-- (tek satırlık CHECK ile) uygulanamaz; start_quiz/publish akışındaki
-- sunucu fonksiyonu doğrular.
-- =========================================================================
create table public.photos (
  id                     uuid primary key default gen_random_uuid(),
  profile_id             uuid not null references public.profiles (id) on delete cascade,
  position               int not null check (position between 1 and 7),
  -- Rastgele/tahmin edilemez depolama yolu (brifing madde 5).
  storage_path           text not null unique,
  contains_other_people  boolean not null default false,
  moderation_status      text not null default 'pending'
                           check (moderation_status in ('pending', 'approved', 'rejected')),
  created_at             timestamptz not null default now(),
  unique (profile_id, position)
);

-- =========================================================================
-- taxonomies / taxonomy_items / taxonomy_adjacency
-- İstemciye hiçbir koşulda açılmaz (brifing bölüm 8, madde 6). Yalnızca
-- pick_distractors() ve profil kurulumundaki get_taxonomy_items() gibi
-- SECURITY DEFINER fonksiyonlar üzerinden servis edilir.
-- =========================================================================
create table public.taxonomies (
  id              int generated always as identity primary key,
  name            text not null,
  question_body   text not null,
  is_active       boolean not null default true
);

create table public.taxonomy_items (
  id            int generated always as identity primary key,
  taxonomy_id   int not null references public.taxonomies (id) on delete cascade,
  label         text not null,
  is_active     boolean not null default true
);

-- Komşuluk çift yönlü kaydedilir: (A,B) eklenince (B,A) da seed/yönetim
-- katmanında eklenmelidir; veritabanı bunu otomatik simetrikleştirmez.
create table public.taxonomy_adjacency (
  item_id           int not null references public.taxonomy_items (id) on delete cascade,
  neighbor_item_id  int not null references public.taxonomy_items (id) on delete cascade,
  primary key (item_id, neighbor_item_id),
  check (item_id <> neighbor_item_id)
);

-- =========================================================================
-- question_templates — global kalıp soru kütüphanesi (herkese açık, ortak)
-- =========================================================================
create table public.question_templates (
  id                  int generated always as identity primary key,
  body                text not null check (char_length(body) between 1 and 300),
  category            text,
  act                 int not null check (act in (1, 2)),
  default_difficulty  text not null check (default_difficulty in ('easy', 'medium', 'hard')),
  taxonomy_id         int references public.taxonomies (id),
  is_active           boolean not null default true
);

-- Sadece taxonomy_id boş olan (sabit şıklı) sorular için.
create table public.template_options (
  id            int generated always as identity primary key,
  template_id   int not null references public.question_templates (id) on delete cascade,
  body          text not null check (char_length(body) between 1 and 150),
  position      int not null,
  unique (template_id, position)
);

create or replace function public.check_template_option_requires_no_taxonomy()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from public.question_templates
    where id = new.template_id and taxonomy_id is not null
  ) then
    raise exception 'template_options yalnızca taxonomy_id boş olan question_templates için eklenebilir';
  end if;
  return new;
end;
$$;

create trigger trg_check_template_option_requires_no_taxonomy
  before insert or update on public.template_options
  for each row execute function public.check_template_option_requires_no_taxonomy();

-- =========================================================================
-- profile_template_answers
-- İSTEMCİYE TAMAMEN KAPALI. Doğru cevap burada duruyor; hem okuma hem
-- yazma yalnızca SECURITY DEFINER fonksiyonlar üzerinden olacak (ör.
-- set_template_answer()) — bu tabloya authenticated rolüne hiç GRANT
-- verilmeyecek.
-- =========================================================================
create table public.profile_template_answers (
  profile_id           uuid not null references public.profiles (id) on delete cascade,
  template_id          int not null references public.question_templates (id) on delete cascade,
  selected_option_id   int references public.template_options (id),
  selected_item_id     int references public.taxonomy_items (id),
  difficulty           text not null check (difficulty in ('easy', 'medium', 'hard')),
  primary key (profile_id, template_id),
  check (
    (selected_option_id is not null)::int + (selected_item_id is not null)::int = 1
  )
);

-- =========================================================================
-- custom_questions / custom_options
-- Kullanıcının kendi yazdığı serbest sorular (act 2). correct_option_id bu
-- tabloda duruyor ama authenticated rolüne SÜTUN BAZLI grant ile açılıyor:
-- sahibi dahil kimse bu sütunu SELECT ile geri okuyamaz (bkz. grants.sql).
-- Düzenleme ekranı bu yüzden "hangisi doğruydu" göstermek yerine baştan
-- seçtirmelidir.
-- =========================================================================
create table public.custom_questions (
  id                  uuid primary key default gen_random_uuid(),
  profile_id          uuid not null references public.profiles (id) on delete cascade,
  body                text not null check (char_length(body) between 1 and 300),
  correct_option_id   uuid,
  is_active           boolean not null default true
);

create table public.custom_options (
  id            uuid primary key default gen_random_uuid(),
  question_id   uuid not null references public.custom_questions (id) on delete cascade,
  body          text not null check (char_length(body) between 1 and 150),
  position      int not null,
  unique (question_id, position)
);

alter table public.custom_questions
  add constraint custom_questions_correct_option_id_fkey
  foreign key (correct_option_id) references public.custom_options (id) on delete restrict;

create or replace function public.check_custom_correct_option_belongs_to_question()
returns trigger
language plpgsql
as $$
begin
  if new.correct_option_id is not null and not exists (
    select 1 from public.custom_options
    where id = new.correct_option_id
      and question_id = new.id
  ) then
    raise exception 'correct_option_id, aynı custom_questions satırına ait bir custom_options satırı değil';
  end if;
  return new;
end;
$$;

create trigger trg_check_custom_correct_option
  before insert or update on public.custom_questions
  for each row execute function public.check_custom_correct_option_belongs_to_question();

-- =========================================================================
-- template_stats — taban oran takibi (global, profile'a değil template'e
-- bağlı). Yalnızca service role okur/yazar; hiçbir authenticated grant yok.
-- =========================================================================
create table public.template_stats (
  id              int generated always as identity primary key,
  template_id     int not null references public.question_templates (id) on delete cascade,
  -- Sabit şıklı sorularda option_id, taksonomi sorularında item_id dolu olur.
  -- İkisi de PK'ye giremez (PK sütunları örtük NOT NULL olur, ama bu ikisi
  -- karşılıklı dışlayıcı ve nullable olmalı) — bu yüzden ayrı bir surrogate
  -- id ve iki kısmi UNIQUE index kullanılıyor.
  option_id       int references public.template_options (id),
  item_id         int references public.taxonomy_items (id),
  selected_count  int not null default 0,
  check (
    (option_id is not null)::int + (item_id is not null)::int = 1
  )
);

create unique index idx_template_stats_unique_option
  on public.template_stats (template_id, option_id) where option_id is not null;

create unique index idx_template_stats_unique_item
  on public.template_stats (template_id, item_id) where item_id is not null;

-- =========================================================================
-- quiz_attempts — yapısal olarak v2 ile aynı
-- =========================================================================
create table public.quiz_attempts (
  id                  uuid primary key default gen_random_uuid(),
  viewer_id           uuid not null references public.profiles (id) on delete cascade,
  target_profile_id   uuid not null references public.profiles (id) on delete cascade,
  status              text not null default 'in_progress'
                        check (status in ('in_progress', 'failed_checkpoint', 'completed')),
  score               int not null default 0 check (score between 0 and 10),
  checkpoint_passed   boolean not null default false,
  unlocked_tier       int not null default 0 check (unlocked_tier in (0, 7, 8)),
  started_at          timestamptz not null default now(),
  completed_at        timestamptz,
  check (viewer_id <> target_profile_id),
  -- Profil başına tek deneme, veritabanı seviyesinde.
  unique (viewer_id, target_profile_id)
);

-- =========================================================================
-- attempt_questions — v3'te yeniden tasarlandı
-- Bir deneme sırasında gösterilen her sorunun sunucu tarafından üretilmiş
-- anlık görüntüsünü (soru metni + şıklar) shown_option_ids içinde taşır;
-- viewer hiçbir zaman question_templates/custom_questions/taxonomy_items'a
-- doğrudan sorgu atmadan quiz'i oynayabilir. Şekli:
--   {"question_body": "...", "options": [{"id": "...", "body": "..."}]}
--
-- correct_option_id ve attempt_answers.selected_option_id `text` — kaynağa
-- göre template_options.id (int), custom_options.id (uuid) ya da
-- taxonomy_items.id (int) taşıyabildiği için tek bir FK tipiyle
-- bağlanamıyor; doğrulama fonksiyon katmanında yapılır.
-- =========================================================================
create table public.attempt_questions (
  attempt_id           uuid not null references public.quiz_attempts (id) on delete cascade,
  position             int not null check (position between 1 and 10),
  template_id          int references public.question_templates (id),
  custom_question_id   uuid references public.custom_questions (id),
  shown_option_ids     jsonb not null,
  correct_option_id    text not null,
  primary key (attempt_id, position),
  check (
    (template_id is not null)::int + (custom_question_id is not null)::int = 1
  )
);

-- =========================================================================
-- attempt_answers — v3'te position bazlı
-- PK, "bir soru bir denemede yalnızca bir kez cevaplanabilir" kuralını
-- veritabanı seviyesinde dayatır.
-- =========================================================================
create table public.attempt_answers (
  attempt_id          uuid not null,
  question_position   int not null,
  selected_option_id  text not null,
  is_correct          boolean not null,
  answered_at         timestamptz not null default now(),
  primary key (attempt_id, question_position),
  foreign key (attempt_id, question_position)
    references public.attempt_questions (attempt_id, position) on delete cascade
);

-- =========================================================================
-- skipped_profiles — YENİ
-- Destede aşağı kaydırılan profiller. Ana desteye geri dönmez, sadece
-- Atlananlar bölümünde görünür.
-- =========================================================================
create table public.skipped_profiles (
  viewer_id           uuid not null references public.profiles (id) on delete cascade,
  target_profile_id   uuid not null references public.profiles (id) on delete cascade,
  skipped_at          timestamptz not null default now(),
  primary key (viewer_id, target_profile_id)
);

-- =========================================================================
-- hidden_profiles
-- =========================================================================
create table public.hidden_profiles (
  viewer_id           uuid not null references public.profiles (id) on delete cascade,
  target_profile_id   uuid not null references public.profiles (id) on delete cascade,
  hidden_until        timestamptz not null,
  primary key (viewer_id, target_profile_id)
);

-- =========================================================================
-- identity_reveals
-- =========================================================================
create table public.identity_reveals (
  id                  uuid primary key default gen_random_uuid(),
  viewer_id           uuid not null references public.profiles (id) on delete cascade,
  target_profile_id   uuid not null references public.profiles (id) on delete cascade,
  revealed_at         timestamptz not null default now()
);

-- =========================================================================
-- conversations / messages
-- =========================================================================
create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  participant_a   uuid not null references public.profiles (id) on delete cascade,
  participant_b   uuid not null references public.profiles (id) on delete cascade,
  status          text not null default 'pending'
                    check (status in ('pending', 'accepted', 'declined', 'blocked')),
  created_at      timestamptz not null default now(),
  check (participant_a <> participant_b)
);

create table public.messages (
  id                    uuid primary key default gen_random_uuid(),
  conversation_id       uuid not null references public.conversations (id) on delete cascade,
  sender_id             uuid not null references public.profiles (id) on delete cascade,
  body                  text not null,
  char_limit_applied    int not null check (char_limit_applied in (50, 100)),
  created_at            timestamptz not null default now(),
  check (char_length(body) <= char_limit_applied)
);

-- =========================================================================
-- reports / blocks
-- =========================================================================
create table public.reports (
  id                    uuid primary key default gen_random_uuid(),
  reporter_id           uuid not null references public.profiles (id) on delete cascade,
  reported_profile_id   uuid not null references public.profiles (id) on delete cascade,
  reason                text not null,
  details               text,
  status                text not null default 'open'
                          check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at            timestamptz not null default now(),
  check (reporter_id <> reported_profile_id)
);

create table public.blocks (
  blocker_id    uuid not null references public.profiles (id) on delete cascade,
  blocked_id    uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- =========================================================================
-- daily_quotas — YZ kotası kaldırıldı
-- =========================================================================
create table public.daily_quotas (
  user_id                 uuid not null references public.profiles (id) on delete cascade,
  date                    date not null default current_date,
  quiz_attempts_used      int not null default 0,
  discover_calls_used     int not null default 0,
  message_requests_used   int not null default 0,
  primary key (user_id, date)
);
