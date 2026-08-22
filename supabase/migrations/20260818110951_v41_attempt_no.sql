-- Farket v4.1 — Migration 3/5: deneme kısıtı (attempt_no).
--
-- İkinci deneme (retry) için gereken temel: (viewer, target) çifti artık
-- TEK değil, en fazla İKİ satır taşıyabiliyor. CHECK olmadan yeni UNIQUE
-- tek başına sınırsız deneme kapısı açar (attempt_no = 3, 4, 5…) — brute
-- force korumasının tamamı bu iki kısıta (UNIQUE + CHECK) birlikte
-- dayanıyor, biri eksik kalırsa diğeri anlamsızlaşır.
--
-- start_quiz/finish_quiz'in attempt_no'yu fiilen KULLANMASI (2. deneme
-- açma, retry_cost düşme, max_tier=8 uygulama) Migration 4'te —
-- burada yalnızca şema hazırlanıyor, davranış henüz değişmiyor
-- (attempt_no her zaman varsayılan 1 ile dolacak, start_quiz hâlâ eskisi
-- gibi ikinci bir deneme insert'ini UNIQUE ihlaliyle reddedecek).

alter table public.quiz_attempts
  add column attempt_no           int not null default 1,
  add column max_tier             int not null default 10,
  add column profile_view_seconds int not null default 0,
  add column credits_spent        int not null default 1;

alter table public.quiz_attempts
  drop constraint quiz_attempts_viewer_id_target_profile_id_key;

alter table public.quiz_attempts
  add constraint quiz_attempts_viewer_target_attempt_key
  unique (viewer_id, target_profile_id, attempt_no);

alter table public.quiz_attempts
  add constraint quiz_attempts_attempt_no_max check (attempt_no <= 2 and attempt_no >= 1);
