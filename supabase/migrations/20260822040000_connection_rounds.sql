-- Farket — bağlantıda sınırsız mesajlaşma, bağlantıdan çıkarma ve soru tekrarının
-- azaltılması (22 Ağustos).
--
-- Ürün kararları:
--   * Bağlantı kurulan çift birbirine sınırsız mesaj gönderebilir. Pratikte bu,
--     kabul edilmiş sohbetteki günlük 300 mesaj kotasının kalkması demek — karakter
--     sınırı zaten yoktu.
--   * Biri diğerini bağlantıdan çıkarabilir. Çıkarma SOHBETİ TAMAMEN KAPATIR ve
--     GERİ ALINAMAZ. Taraflar yeniden iletişim kurmak için birbirlerinin quizini
--     BAŞTAN çözmek zorunda.
--   * Yeni quiz turunda daha önce görülmemiş sorular öne alınır.
--
-- Karşılaşılan yapısal kısıtlar ve nasıl çözüldükleri:
--   * conversations'da çift başına ömür boyu TEK satır var
--     (idx_conversations_unique_pair). Bu yüzden "kapat, yenisini aç" mümkün değil;
--     aynı satır kapatılıp koşullar sağlanınca yeniden açılıyor.
--   * quiz_attempts'te deneme sayısı CHECK ile 1..2 arasında sabit. Çıkarma sonrası
--     yeniden quiz çözülebilmesi için TUR (round_no) kavramı ekleniyor: sınır artık
--     "tur başına 2 deneme".

-- =========================================================================
-- 1) _is_connection — "bu sohbette karşılıklı mesajlaşma oldu mu".
--
-- Tanım şimdiye kadar get_my_connections ve get_engagement_funnel içinde ayrı ayrı
-- yazılıydı; üçüncü kullanım yeri (send_message) eklenirken tek kaynağa alındı.
-- Yalnızca MESAJLARA bakar, sohbetin durumuna bakmaz: "bağlantı kuruldu mu" ile
-- "hâlâ bağlantılılar mı" farklı sorular. İkincisi için çağıran taraf ayrıca
-- status kontrol eder (kapanmış sohbet geçmişte bağlantıydı ama artık değil).
-- =========================================================================
create or replace function public._is_connection(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.conversations c
      join public.messages m on m.conversation_id = c.id
     where c.id = p_conversation_id
     group by c.id, c.participant_a, c.participant_b
    having count(*) filter (where m.sender_id = c.participant_a) > 0
       and count(*) filter (where m.sender_id = c.participant_b) > 0
  );
$$;

revoke execute on function public._is_connection(uuid) from public;

comment on function public._is_connection(uuid) is
  'Sohbette iki tarafın da en az bir mesajı var mı — "bağlantı" tanımının tek kaynağı.';

-- =========================================================================
-- 2) connection_removals + tur hesabı.
--
-- Yüzey anahtar yerine kendi id'si var: çift birden fazla kez bağlantı kurup
-- çıkarabilir (her seferinde quizler yeniden çözülerek), (remover, removed)
-- üzerinde PK olsaydı tur sayısı ikiyle sınırlanırdı.
-- =========================================================================
create table public.connection_removals (
  id          uuid primary key default gen_random_uuid(),
  remover_id  uuid not null references public.profiles (id) on delete cascade,
  removed_id  uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  check (remover_id <> removed_id)
);

create index idx_connection_removals_pair
  on public.connection_removals (least(remover_id, removed_id), greatest(remover_id, removed_id));

alter table public.connection_removals enable row level security;
-- Politika YOK: tabloya yalnızca SECURITY DEFINER fonksiyonlar erişir.

comment on table public.connection_removals is
  'Bağlantıdan çıkarma kayıtları. Hem denetim izi hem de bir çiftin quiz turunu (round_no) belirleyen sayaç.';

create or replace function public._current_round(p_a uuid, p_b uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select 1 + (
    select count(*)
      from public.connection_removals r
     where least(r.remover_id, r.removed_id) = least(p_a, p_b)
       and greatest(r.remover_id, r.removed_id) = greatest(p_a, p_b)
  )::int;
$$;

revoke execute on function public._current_round(uuid, uuid) from public;

comment on function public._current_round(uuid, uuid) is
  'Bir çiftin güncel quiz turu: 1 + aralarındaki bağlantıdan çıkarma sayısı.';

-- =========================================================================
-- 3) quiz_attempts.round_no — "tur başına 2 deneme".
-- attempt_no CHECK'i (1..2) DEĞİŞMİYOR, yalnızca kapsamı turla sınırlanıyor.
-- =========================================================================
alter table public.quiz_attempts
  add column round_no int not null default 1 check (round_no >= 1);

alter table public.quiz_attempts
  drop constraint quiz_attempts_viewer_target_attempt_key;

alter table public.quiz_attempts
  add constraint quiz_attempts_viewer_target_round_attempt_key
  unique (viewer_id, target_profile_id, round_no, attempt_no);

comment on column public.quiz_attempts.round_no is
  'Bağlantıdan çıkarma sonrası başlayan yeni quiz turu. Ömürlük 2 deneme sınırı tur başına uygulanır.';

-- =========================================================================
-- 4) remove_connection — bağlantıdan çıkar.
--
-- Geri alınamaz: geri alma RPC'si bilerek yazılmadı. İstemci, çağırmadan önce
-- sonucu açıkça anlatan bir onay diyaloğu gösterir.
--
-- Karşı tarafa bildirim GÖNDERİLMEZ: "seni bağlantıdan çıkardı" bildirimi
-- düşmanca bir sinyal ve gereksiz — kapanan sohbet zaten görünür.
-- =========================================================================
create or replace function public.remove_connection(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_conv record;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  if p_profile_id is null or p_profile_id = v_uid then
    raise exception 'Geçersiz profil';
  end if;

  select * into v_conv
    from public.conversations
    where (participant_a = v_uid and participant_b = p_profile_id)
       or (participant_a = p_profile_id and participant_b = v_uid)
    for update;

  if not found or v_conv.status not in ('pending', 'accepted') then
    raise exception 'Bu kişiyle aktif bir bağlantın yok';
  end if;

  if not public._is_connection(v_conv.id) then
    raise exception 'Bu kişiyle bağlantın yok (bağlantı için ikinizin de mesaj göndermiş olması gerekir)';
  end if;

  update public.conversations set status = 'closed' where id = v_conv.id;

  insert into public.connection_removals (remover_id, removed_id)
    values (v_uid, p_profile_id);

  -- Yeni tur temiz başlasın: önceki turun gizleme cezası yeni turu engellemesin.
  delete from public.hidden_profiles
    where (viewer_id = v_uid and target_profile_id = p_profile_id)
       or (viewer_id = p_profile_id and target_profile_id = v_uid);

  return jsonb_build_object(
    'removed', true,
    'next_round', public._current_round(v_uid, p_profile_id)
  );
end;
$$;

revoke execute on function public.remove_connection(uuid) from public;
grant execute on function public.remove_connection(uuid) to authenticated;

comment on function public.remove_connection(uuid) is
  'Bağlantıyı sonlandırır: sohbeti kapatır, yeni quiz turu başlatır. Geri alınamaz.';

-- =========================================================================
-- 5) get_my_connections — kapanmış sohbetler listede görünmesin.
-- Tek değişiklik: status filtresi + ortak _is_connection tanımı.
-- =========================================================================
create or replace function public.get_my_connections()
returns table (
  profile_id       uuid,
  username         text,
  conversation_id  uuid,
  connected_at     timestamptz,
  last_message_at  timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  return query
    select
      p.id,
      p.username,
      c.id,
      greatest(
        min(m.created_at) filter (where m.sender_id = v_uid),
        min(m.created_at) filter (where m.sender_id <> v_uid)
      ),
      max(m.created_at)
    from public.conversations c
    join public.profiles p
      on p.id = case when c.participant_a = v_uid then c.participant_b else c.participant_a end
    join public.messages m
      on m.conversation_id = c.id
    where (c.participant_a = v_uid or c.participant_b = v_uid)
      -- Bağlantıdan çıkarılmış (kapatılmış) sohbetler artık bağlantı değil.
      and c.status in ('pending', 'accepted')
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_uid and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_uid)
      )
    group by p.id, p.username, c.id
    having count(*) filter (where m.sender_id = v_uid) > 0
       and count(*) filter (where m.sender_id <> v_uid) > 0
    order by max(m.created_at) desc;
end;
$$;

revoke execute on function public.get_my_connections() from public;
grant execute on function public.get_my_connections() to authenticated;
