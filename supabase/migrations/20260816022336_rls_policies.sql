-- Farket: RLS politikaları (v3)
-- Kural: her tabloda RLS açık, varsayılan reddet. İzin verilen her erişim
-- ayrı ayrı yazılır. Burada yazılmayan her (tablo, işlem, rol) kombinasyonu
-- reddedilir.
--
-- Sütun bazlı gizlilik gereken yerlerde (custom_questions.correct_option_id,
-- attempt_questions.correct_option_id) satır politikası yetmiyor; bunlar
-- grants.sql'de SÜTUN BAZLI GRANT ile kapatılıyor. taxonomy_items,
-- taxonomy_adjacency, profile_template_answers, template_stats'a hiçbir
-- authenticated erişimi verilmiyor (aşağıda hiç select politikası yok) —
-- bunlar yalnızca SECURITY DEFINER fonksiyonlar üzerinden servis edilecek.

alter table public.cities                    enable row level security;
alter table public.districts                 enable row level security;
alter table public.profiles                  enable row level security;
alter table public.identity_card             enable row level security;
alter table public.photos                    enable row level security;
alter table public.taxonomies                enable row level security;
alter table public.taxonomy_items            enable row level security;
alter table public.taxonomy_adjacency        enable row level security;
alter table public.question_templates        enable row level security;
alter table public.template_options          enable row level security;
alter table public.profile_template_answers  enable row level security;
alter table public.custom_questions          enable row level security;
alter table public.custom_options            enable row level security;
alter table public.template_stats            enable row level security;
alter table public.quiz_attempts             enable row level security;
alter table public.attempt_questions         enable row level security;
alter table public.attempt_answers           enable row level security;
alter table public.skipped_profiles          enable row level security;
alter table public.hidden_profiles           enable row level security;
alter table public.identity_reveals          enable row level security;
alter table public.conversations             enable row level security;
alter table public.messages                  enable row level security;
alter table public.reports                   enable row level security;
alter table public.blocks                    enable row level security;
alter table public.daily_quotas              enable row level security;

-- =========================================================================
-- cities / districts — herkese açık kapalı referans listeleri
-- =========================================================================
create policy cities_select_active
  on public.cities for select
  to authenticated
  using (is_active);

create policy districts_select_active
  on public.districts for select
  to authenticated
  using (is_active);

-- =========================================================================
-- profiles — sadece kendi kaydı. Başkasının profili yalnızca
-- get_public_profile() fonksiyonu üzerinden.
-- =========================================================================
create policy profiles_select_own
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()));

create policy profiles_insert_own
  on public.profiles for insert
  to authenticated
  with check (id = (select auth.uid()));

create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- =========================================================================
-- identity_card — başkaları hiç kimse doğrudan okuyamaz (yalnızca
-- reveal_identity() üzerinden). Sahibi kendi künyesini okuyabilir/yazabilir.
-- =========================================================================
create policy identity_card_select_own
  on public.identity_card for select
  to authenticated
  using (profile_id = (select auth.uid()));

create policy identity_card_insert_own
  on public.identity_card for insert
  to authenticated
  with check (profile_id = (select auth.uid()));

create policy identity_card_update_own
  on public.identity_card for update
  to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- =========================================================================
-- photos — metadata: sadece sahibi doğrudan okur. Başkasının fotoğraf
-- listesini görmek get_profile_photos() üzerinden olacak.
-- =========================================================================
create policy photos_select_own
  on public.photos for select
  to authenticated
  using (profile_id = (select auth.uid()));

create policy photos_insert_own
  on public.photos for insert
  to authenticated
  with check (profile_id = (select auth.uid()));

create policy photos_update_own
  on public.photos for update
  to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy photos_delete_own
  on public.photos for delete
  to authenticated
  using (profile_id = (select auth.uid()));

-- =========================================================================
-- taxonomies — kategori metadatası (soru gövdesi, ad); havuzun kendisi
-- (taxonomy_items) ve komşuluk (taxonomy_adjacency) burada DEĞİL, onlara
-- hiç select politikası yok.
-- =========================================================================
create policy taxonomies_select_active
  on public.taxonomies for select
  to authenticated
  using (is_active);

-- =========================================================================
-- question_templates / template_options — global kütüphane, herkese açık.
-- =========================================================================
create policy question_templates_select_active
  on public.question_templates for select
  to authenticated
  using (is_active);

create policy template_options_select_if_template_active
  on public.template_options for select
  to authenticated
  using (
    exists (
      select 1 from public.question_templates qt
      where qt.id = template_options.template_id and qt.is_active
    )
  );

-- =========================================================================
-- custom_questions / custom_options — sahibi kendi sorularını yönetir.
-- correct_option_id sütun bazlı GRANT ile SELECT'ten hariç tutuluyor
-- (grants.sql); burada RLS yalnızca satır sahipliğini kontrol ediyor.
-- =========================================================================
create policy custom_questions_select_own
  on public.custom_questions for select
  to authenticated
  using (profile_id = (select auth.uid()));

create policy custom_questions_insert_own
  on public.custom_questions for insert
  to authenticated
  with check (profile_id = (select auth.uid()));

create policy custom_questions_update_own
  on public.custom_questions for update
  to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

create policy custom_options_select_own
  on public.custom_options for select
  to authenticated
  using (
    exists (
      select 1 from public.custom_questions cq
      where cq.id = custom_options.question_id and cq.profile_id = (select auth.uid())
    )
  );

create policy custom_options_insert_own
  on public.custom_options for insert
  to authenticated
  with check (
    exists (
      select 1 from public.custom_questions cq
      where cq.id = custom_options.question_id and cq.profile_id = (select auth.uid())
    )
  );

create policy custom_options_update_own
  on public.custom_options for update
  to authenticated
  using (
    exists (
      select 1 from public.custom_questions cq
      where cq.id = custom_options.question_id and cq.profile_id = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.custom_questions cq
      where cq.id = custom_options.question_id and cq.profile_id = (select auth.uid())
    )
  );

create policy custom_options_delete_own
  on public.custom_options for delete
  to authenticated
  using (
    exists (
      select 1 from public.custom_questions cq
      where cq.id = custom_options.question_id and cq.profile_id = (select auth.uid())
    )
  );

-- =========================================================================
-- quiz_attempts — sadece kendi denemeleri. Yazma yok (fonksiyon yazar).
-- =========================================================================
create policy quiz_attempts_select_own
  on public.quiz_attempts for select
  to authenticated
  using (viewer_id = (select auth.uid()));

-- =========================================================================
-- attempt_questions — kendi aktif denemesine ait satırları görebilir.
-- correct_option_id sütun bazlı GRANT ile hariç tutuluyor (grants.sql).
-- Yazma yok (start_quiz fonksiyonu doldurur).
-- =========================================================================
create policy attempt_questions_select_own
  on public.attempt_questions for select
  to authenticated
  using (
    exists (
      select 1 from public.quiz_attempts qa
      where qa.id = attempt_questions.attempt_id
        and qa.viewer_id = (select auth.uid())
    )
  );

-- =========================================================================
-- attempt_answers — sadece kendi cevapları. Yazma yok (fonksiyon yazar).
-- =========================================================================
create policy attempt_answers_select_own
  on public.attempt_answers for select
  to authenticated
  using (
    exists (
      select 1 from public.quiz_attempts qa
      where qa.id = attempt_answers.attempt_id
        and qa.viewer_id = (select auth.uid())
    )
  );

-- =========================================================================
-- skipped_profiles — sadece kendi kayıtları. Yazma yok
-- (skip_profile/unskip_profile fonksiyonları yazar).
-- =========================================================================
create policy skipped_profiles_select_own
  on public.skipped_profiles for select
  to authenticated
  using (viewer_id = (select auth.uid()));

-- =========================================================================
-- hidden_profiles — sadece kendi kayıtları. Yazma yok (fonksiyon yazar).
-- =========================================================================
create policy hidden_profiles_select_own
  on public.hidden_profiles for select
  to authenticated
  using (viewer_id = (select auth.uid()));

-- =========================================================================
-- identity_reveals — hem gösterimi yapan hem de künyesi açılan taraf
-- kendi bildirimi için görebilir. Yazma yok (fonksiyon yazar).
-- =========================================================================
create policy identity_reveals_select_participant
  on public.identity_reveals for select
  to authenticated
  using (
    viewer_id = (select auth.uid())
    or target_profile_id = (select auth.uid())
  );

-- =========================================================================
-- conversations — sadece konuşmanın tarafları. Yazma fonksiyon üzerinden.
-- =========================================================================
create policy conversations_select_participant
  on public.conversations for select
  to authenticated
  using (
    participant_a = (select auth.uid())
    or participant_b = (select auth.uid())
  );

-- =========================================================================
-- messages — sadece konuşmanın tarafları. Yazma fonksiyon üzerinden.
-- =========================================================================
create policy messages_select_participant
  on public.messages for select
  to authenticated
  using (
    exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id
        and (c.participant_a = (select auth.uid()) or c.participant_b = (select auth.uid()))
    )
  );

-- =========================================================================
-- reports — kullanıcı kendi gönderdiği şikayetleri görebilir ve
-- gönderebilir. Durumu yalnızca moderasyon (service role) günceller.
-- =========================================================================
create policy reports_select_own
  on public.reports for select
  to authenticated
  using (reporter_id = (select auth.uid()));

create policy reports_insert_own
  on public.reports for insert
  to authenticated
  with check (reporter_id = (select auth.uid()));

-- =========================================================================
-- blocks — kullanıcı kendi engelleme listesini görebilir, ekleyebilir ve
-- kaldırabilir.
-- =========================================================================
create policy blocks_select_own
  on public.blocks for select
  to authenticated
  using (blocker_id = (select auth.uid()));

create policy blocks_insert_own
  on public.blocks for insert
  to authenticated
  with check (blocker_id = (select auth.uid()));

create policy blocks_delete_own
  on public.blocks for delete
  to authenticated
  using (blocker_id = (select auth.uid()));

-- =========================================================================
-- daily_quotas — sadece kendi kaydı. Yazma yok (service role günceller).
-- =========================================================================
create policy daily_quotas_select_own
  on public.daily_quotas for select
  to authenticated
  using (user_id = (select auth.uid()));
