-- Farket — kaybolan fotoğraf/video mesajı (22 Ağustos).
--
-- ÜRÜN KURALI: iki taraf da BİRBİRİNİN quizinden 9 veya 10 ile çıkmışsa o sohbette
-- kaybolan medya gönderme açılır:
--   * deklanşöre bir kez dokun  -> fotoğraf
--   * basılı tut                -> en fazla 10 saniye video (sesli/sessiz, gönderen seçer)
-- Medya bir kez izlenir, açılınca kaybolur. Filtre/kamera ayarları tamamen istemci
-- tarafındadır, burayı ilgilendirmez.
--
-- 9+ eşiği mevcut ödül merdiveninin doğal devamı: ikinci denemede tavan 8 olduğu için
-- (bkz. start_quiz, max_tier) 9+ yalnızca İLK denemede kazanılabiliyor, dolayısıyla
-- karşılıklı 9+ kendiliğinden nadir. Bağlantı turlarıyla da tutarlı: bir taraf
-- diğerini bağlantıdan çıkarırsa yeni turda bu hak yeniden kazanılmak zorunda.
--
-- SAKLAMA POLİTİKASI (kullanıcı kararı):
--   * Medya açılır açılmaz kullanıcı için biter; sunucudaki dosya 1 SAAT daha durur.
--   * Bu 1 saat şikâyet payı: alıcı şikâyet ederse kopya 30 gün donar ve incelenebilir.
--     Şikâyet gelmezse süpürücü siler.
--   * Hiç açılmayan medya 24 saat sonra silinir.
--   * Kullanıcıya verilen söz "kimse kaydedemez" DEĞİL, "biz saklamıyoruz, karşı taraf
--     ekran kaydı alabilir" — istemci bu metni göstermek zorunda (FLAG_SECURE ekran
--     kaydının maliyetini artırır, garanti vermez).
--
-- Dosyaların fiziksel silinmesi Postgres'ten YAPILAMIYOR (storage.objects üzerindeki
-- protect_objects_delete trigger'ı engelliyor, bkz. 20260817040000). Bu yüzden
-- purge-deleted-photos ile aynı desen: DB fonksiyonu silinecek yolları döndürür,
-- Edge Function Storage'dan siler.

-- =========================================================================
-- 1) Bucket. 10 saniyelik video için 15 MB fazlasıyla yeterli.
-- =========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ephemeral-media', 'ephemeral-media', false, 15728640, array['video/mp4', 'image/jpeg'])
on conflict (id) do nothing;

-- =========================================================================
-- 2) ephemeral_media
-- =========================================================================
create table public.ephemeral_media (
  id                uuid primary key default gen_random_uuid(),
  conversation_id   uuid not null references public.conversations (id) on delete cascade,
  sender_id         uuid not null references public.profiles (id) on delete cascade,
  media_type        text not null check (media_type in ('photo', 'video')),
  storage_path      text not null,
  -- Yalnızca videoda dolu; fotoğrafta anlamsız olduğu için null olmak zorunda.
  duration_ms       int,
  has_audio         boolean,
  status            text not null default 'pending'
                      check (status in ('pending', 'sent', 'opened', 'purged')),
  created_at        timestamptz not null default now(),
  opened_at         timestamptz,
  -- Dosyanın silinebileceği an. Gönderimde 24 saat (hiç açılmazsa), açılışta
  -- 1 saate çekilir (şikâyet payı).
  delete_after      timestamptz not null default now() + interval '24 hours',
  -- Şikâyet edilirse süpürücü bu tarihe kadar dosyaya dokunmaz.
  report_hold_until timestamptz,
  constraint ephemeral_media_video_fields check (
    (media_type = 'video' and duration_ms between 1 and 10000 and has_audio is not null)
    or (media_type = 'photo' and duration_ms is null and has_audio is null)
  )
);

create index idx_ephemeral_media_conversation on public.ephemeral_media (conversation_id, created_at desc);
create index idx_ephemeral_media_sweep on public.ephemeral_media (delete_after) where status <> 'purged';

alter table public.ephemeral_media enable row level security;

-- Sohbetin iki tarafı da satırı görebilir (istemci "gönderildi / açıldı" durumunu
-- buradan okuyor; realtime akışı da bunun üzerinden çalışır). Yazma yalnızca RPC ile.
create policy ephemeral_media_select_participant
  on public.ephemeral_media for select
  to authenticated
  using (
    exists (
      select 1 from public.conversations c
      where c.id = ephemeral_media.conversation_id
        and (c.participant_a = (select auth.uid()) or c.participant_b = (select auth.uid()))
    )
  );

comment on table public.ephemeral_media is
  'Bir kez izlenen, açılınca silinen fotoğraf/video mesajları. Karşılıklı 9+ quiz skoruyla açılır.';

-- messages'a bağ: sohbet zaman çizelgesi tek kaynakta kalsın ve realtime akışı
-- (MessagingRepository.postgresChangeFlow) değişmeden çalışsın diye kaybolan medya
-- da normal bir mesaj satırı olarak görünüyor.
alter table public.messages
  add column ephemeral_media_id uuid references public.ephemeral_media (id) on delete set null;

-- =========================================================================
-- 3) Storage politikası. Yükleme yalnızca gönderene ve kendi klasörüne.
-- İNDİRME POLİTİKASI YOK: dosya yalnızca open_ephemeral_media'nın döndürdüğü
-- kısa ömürlü imzalı URL ile açılıyor — "bir kez izlenir" kuralı politikayla
-- değil akışla garanti ediliyor.
-- =========================================================================
create policy ephemeral_media_insert_own
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'ephemeral-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f-]{36}\.(mp4|jpg)$')
  );

-- =========================================================================
-- 4) can_send_ephemeral_media — karşılıklı 9+ kapısı.
-- =========================================================================
create or replace function public.can_send_ephemeral_media(p_conversation_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_conv  record;
  v_other uuid;
  v_round int;
begin
  if v_uid is null then
    return false;
  end if;

  select * into v_conv from public.conversations where id = p_conversation_id;

  if not found or v_conv.status <> 'accepted' then
    return false;
  end if;

  if v_conv.participant_a = v_uid then
    v_other := v_conv.participant_b;
  elsif v_conv.participant_b = v_uid then
    v_other := v_conv.participant_a;
  else
    return false;
  end if;

  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = v_uid and b.blocked_id = v_other)
       or (b.blocker_id = v_other and b.blocked_id = v_uid)
  ) then
    return false;
  end if;

  v_round := public._current_round(v_uid, v_other);

  -- İKİ TARAF DA: güncel turda, karşısındakinin quizini 9+ ile bitirmiş olmalı.
  return exists (
    select 1 from public.quiz_attempts
    where viewer_id = v_uid and target_profile_id = v_other
      and round_no = v_round and status = 'completed' and unlocked_tier >= 9
  ) and exists (
    select 1 from public.quiz_attempts
    where viewer_id = v_other and target_profile_id = v_uid
      and round_no = v_round and status = 'completed' and unlocked_tier >= 9
  );
end;
$fn$;

revoke execute on function public.can_send_ephemeral_media(uuid) from public;
grant execute on function public.can_send_ephemeral_media(uuid) to authenticated;

comment on function public.can_send_ephemeral_media(uuid) is
  'Sohbette kaybolan medya gönderme açık mı: iki taraf da güncel turda birbirinin quizini 9+ ile bitirmiş olmalı.';

-- =========================================================================
-- 5) create_ephemeral_media — yükleme öncesi kayıt.
--
-- İki aşamalı: önce satır + yol ayrılıyor, dosya yüklendikten sonra
-- finalize_ephemeral_media mesajı görünür kılıyor. Böylece yükleme yarıda
-- kalırsa sohbette hiç açılamayacak bir medya kartı kalmıyor.
-- =========================================================================
create or replace function public.create_ephemeral_media(
  p_conversation_id uuid,
  p_media_type      text,
  p_duration_ms     int default null,
  p_has_audio       boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid  uuid := (select auth.uid());
  v_id   uuid := gen_random_uuid();
  v_path text;
  v_ext  text;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  if p_media_type not in ('photo', 'video') then
    raise exception 'Geçersiz medya türü';
  end if;

  if not public.can_send_ephemeral_media(p_conversation_id) then
    raise exception 'Kaybolan medya bu sohbette açık değil (ikinizin de birbirinizin quizini en az 9 doğruyla bitirmesi gerekiyor)';
  end if;

  if p_media_type = 'video' then
    if p_duration_ms is null or p_duration_ms <= 0 or p_duration_ms > 10000 then
      raise exception 'Video en fazla 10 saniye olabilir';
    end if;
    v_ext := 'mp4';
  else
    v_ext := 'jpg';
  end if;

  v_path := v_uid::text || '/' || v_id::text || '.' || v_ext;

  insert into public.ephemeral_media
    (id, conversation_id, sender_id, media_type, storage_path, duration_ms, has_audio)
    values (
      v_id, p_conversation_id, v_uid, p_media_type, v_path,
      case when p_media_type = 'video' then p_duration_ms end,
      case when p_media_type = 'video' then coalesce(p_has_audio, true) end
    );

  return jsonb_build_object('media_id', v_id, 'storage_path', v_path);
end;
$fn$;

revoke execute on function public.create_ephemeral_media(uuid, text, int, boolean) from public;
grant execute on function public.create_ephemeral_media(uuid, text, int, boolean) to authenticated;

-- =========================================================================
-- 6) finalize_ephemeral_media — dosya yüklendi, mesajı görünür kıl.
-- =========================================================================
create or replace function public.finalize_ephemeral_media(p_media_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_media record;
  v_msg   uuid;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_media from public.ephemeral_media where id = p_media_id for update;

  if not found or v_media.sender_id <> v_uid then
    raise exception 'Bu medya sana ait değil';
  end if;

  if v_media.status <> 'pending' then
    raise exception 'Bu medya zaten gönderildi';
  end if;

  update public.ephemeral_media set status = 'sent' where id = p_media_id;

  -- body boş bırakılmıyor: sohbet listesi önizlemesi ve export_my_data gibi
  -- düz metin okuyan yerlerde anlamlı bir karşılığı olsun.
  insert into public.messages (conversation_id, sender_id, body, ephemeral_media_id)
    values (
      v_media.conversation_id, v_uid,
      case when v_media.media_type = 'video' then 'Video gönderildi' else 'Fotoğraf gönderildi' end,
      p_media_id
    )
    returning id into v_msg;

  return jsonb_build_object('message_id', v_msg);
end;
$fn$;

revoke execute on function public.finalize_ephemeral_media(uuid) from public;
grant execute on function public.finalize_ephemeral_media(uuid) to authenticated;

-- =========================================================================
-- 7) open_ephemeral_media — bir kez izleme.
--
-- Yalnızca ALICI çağırabilir ve yalnızca bir kez: ikinci çağrı hata verir.
-- Açılışta silinme zamanı 1 saate çekilir (şikâyet payı).
-- =========================================================================
create or replace function public.open_ephemeral_media(p_media_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_media record;
  v_conv  record;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_media from public.ephemeral_media where id = p_media_id for update;

  if not found or v_media.status = 'purged' then
    raise exception 'Bu medya artık yok';
  end if;

  select * into v_conv from public.conversations where id = v_media.conversation_id;

  if v_conv.participant_a <> v_uid and v_conv.participant_b <> v_uid then
    raise exception 'Bu sohbet sana ait değil';
  end if;

  if v_media.sender_id = v_uid then
    raise exception 'Kendi gönderdiğin medyayı izleyemezsin';
  end if;

  if v_media.opened_at is not null then
    raise exception 'Bu medya zaten izlendi';
  end if;

  if v_media.status <> 'sent' then
    raise exception 'Bu medya henüz hazır değil';
  end if;

  update public.ephemeral_media
    set status = 'opened',
        opened_at = now(),
        delete_after = now() + interval '1 hour'
    where id = p_media_id;

  -- Gönderene "açıldı" bilgisi ayrı bir bildirim tipiyle değil, ephemeral_media
  -- satırındaki değişiklikle veriliyor; istemci zaten sohbetin realtime akışını
  -- dinliyor.
  return jsonb_build_object(
    'storage_path', v_media.storage_path,
    'media_type', v_media.media_type,
    'duration_ms', v_media.duration_ms
  );
end;
$fn$;

revoke execute on function public.open_ephemeral_media(uuid) from public;
grant execute on function public.open_ephemeral_media(uuid) to authenticated;

-- =========================================================================
-- 8) report_ephemeral_media — şikâyet payı içinde kopyayı dondur.
-- =========================================================================
create or replace function public.report_ephemeral_media(p_media_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_media record;
  v_conv  record;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_media from public.ephemeral_media where id = p_media_id for update;

  if not found or v_media.status = 'purged' then
    raise exception 'Bu medya artık yok, şikâyet edilemez';
  end if;

  select * into v_conv from public.conversations where id = v_media.conversation_id;

  if v_conv.participant_a <> v_uid and v_conv.participant_b <> v_uid then
    raise exception 'Bu sohbet sana ait değil';
  end if;

  if v_media.sender_id = v_uid then
    raise exception 'Kendi gönderdiğin medyayı şikâyet edemezsin';
  end if;

  update public.ephemeral_media
    set report_hold_until = now() + interval '30 days'
    where id = p_media_id;

  insert into public.reports (reporter_id, reported_profile_id, reason, details)
    values (v_uid, v_media.sender_id, coalesce(p_reason, 'ephemeral_media'),
            'ephemeral_media_id=' || p_media_id::text);
end;
$fn$;

revoke execute on function public.report_ephemeral_media(uuid, text) from public;
grant execute on function public.report_ephemeral_media(uuid, text) to authenticated;

-- =========================================================================
-- 9) collect_expired_ephemeral_media — süpürücü.
--
-- Silinecek Storage yollarını döndürür ve satırları 'purged' işaretler. Fiziksel
-- silmeyi Edge Function yapar (Postgres storage.objects'ten silemiyor).
-- Hiçbir role EXECUTE verilmez: yalnızca postgres/pg_cron.
-- =========================================================================
create or replace function public.collect_expired_ephemeral_media()
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_paths text[];
begin
  with expired as (
    update public.ephemeral_media
       set status = 'purged'
     where status <> 'purged'
       and delete_after < now()
       and (report_hold_until is null or report_hold_until < now())
    returning storage_path
  )
  select coalesce(array_agg(storage_path), '{}') into v_paths from expired;

  return jsonb_build_object('paths', v_paths, 'count', coalesce(array_length(v_paths, 1), 0));
end;
$fn$;

revoke execute on function public.collect_expired_ephemeral_media() from public;

comment on function public.collect_expired_ephemeral_media() is
  'Süresi dolmuş kaybolan medyayı purged işaretler ve Storage yollarını döndürür. Yalnızca postgres (Edge Function/pg_cron).';
