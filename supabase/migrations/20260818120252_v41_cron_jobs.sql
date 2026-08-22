-- Farket v4.1 — sonraki fazlar, Faz 3/6: süre dolumu + emniyet valfi.
--
-- İkisi de yalnızca service role/pg_cron tarafından çalıştırılır,
-- authenticated'a hiç EXECUTE verilmez (purge_deleted_accounts ile aynı
-- desen).

-- =========================================================================
-- 1) conversations.status -> 'expired' eklendi.
-- =========================================================================
alter table public.conversations drop constraint conversations_status_check;
alter table public.conversations add constraint conversations_status_check
  check (status in ('pending', 'accepted', 'declined', 'blocked', 'closed', 'expired'));

-- =========================================================================
-- 2) expire_pending_conversations — 7 günü dolan mesaj isteklerini
-- kapatır, gönderene (kimliksiz) request_expired bildirimi yollar.
-- =========================================================================
create or replace function public.expire_pending_conversations()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conv  record;
  v_count int := 0;
begin
  for v_conv in
    select id, participant_a from public.conversations
    where status = 'pending' and expires_at < now()
  loop
    update public.conversations set status = 'expired' where id = v_conv.id;
    perform public._notify(v_conv.participant_a, 'request_expired', null, null, v_conv.id, '{}'::jsonb);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute on function public.expire_pending_conversations() from public;

-- =========================================================================
-- 3) release_stale_hides — emniyet valfi. Her yayınlanmış/şehri olan
-- profil için "kaç profil keşfedebilir" sayısını discover_profiles'ın
-- KENDİ filtre kümesiyle (limitsiz) hesaplar; 20'nin altındaysa o
-- viewer'ın en eski (henüz retry_used olmayan, süresi dolmamış)
-- gizlemelerini erken serbest bırakır (available_at=now(),
-- released_early=true) — tam olarak eksik kadar.
--
-- Performans notu: bu O(kullanıcı sayısı × discover_profiles benzeri
-- sorgu) bir toplu iş — günde bir kez (pg_cron) çalışacak şekilde
-- tasarlandı, istek başına (request-time) DEĞİL.
-- =========================================================================
create or replace function public.release_stale_hides()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer         record;
  v_visible_count  int;
  v_released       int := 0;
  v_hide           record;
begin
  for v_viewer in
    select id, city_id from public.profiles where status = 'published' and city_id is not null
  loop
    select count(*) into v_visible_count
      from public.profiles p
      where p.id <> v_viewer.id
        and p.status = 'published'
        and p.city_id = v_viewer.city_id
        and p.username is not null
        and exists (
          select 1 from public.photos ph
          where ph.profile_id = p.id and ph.position = 1 and ph.moderation_status = 'approved'
        )
        and not exists (
          select 1 from public.blocks b
          where (b.blocker_id = v_viewer.id and b.blocked_id = p.id)
             or (b.blocker_id = p.id and b.blocked_id = v_viewer.id)
        )
        and not exists (
          select 1 from public.hidden_profiles h
          where h.viewer_id = v_viewer.id and h.target_profile_id = p.id
            and (h.retry_used or h.available_at > now())
        )
        and not exists (
          select 1 from public.skipped_profiles s
          where s.viewer_id = v_viewer.id and s.target_profile_id = p.id
        )
        and not exists (
          select 1 from public.quiz_attempts qa2
          where qa2.viewer_id = v_viewer.id and qa2.target_profile_id = p.id
        );

    if v_visible_count < 20 then
      for v_hide in
        select viewer_id, target_profile_id from public.hidden_profiles
        where viewer_id = v_viewer.id and retry_used = false and available_at > now()
        order by available_at asc
        limit (20 - v_visible_count)
      loop
        update public.hidden_profiles
          set available_at = now(), released_early = true
          where viewer_id = v_hide.viewer_id and target_profile_id = v_hide.target_profile_id;
        v_released := v_released + 1;
      end loop;
    end if;
  end loop;

  return v_released;
end;
$$;

revoke execute on function public.release_stale_hides() from public;

-- =========================================================================
-- 4) pg_cron zamanlaması — purge-deleted-accounts-daily ile aynı desen.
-- =========================================================================
select cron.schedule(
  'expire-pending-conversations-daily',
  '0 4 * * *',
  $$select public.expire_pending_conversations();$$
);

select cron.schedule(
  'release-stale-hides-daily',
  '0 5 * * *',
  $$select public.release_stale_hides();$$
);
