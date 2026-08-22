-- Farket: discover_profiles, get_public_profile, skip_profile,
-- unskip_profile (brifing v3, bölüm 9 adım 8)
--
-- Tasarım notları:
--   * discover_profiles'a p_limit parametresi eklendi (brifingde yok) —
--     kaydırmalı deste kavramı doğası gereği toplu değil, kademeli
--     yükleme gerektirir; varsayılan 20.
--   * "Çözülme oranı" = tamamlanmış (completed veya failed_checkpoint)
--     denemeler arasında unlocked_tier > 0 olanların yüzdesi. Hiç deneme
--     yoksa null döner (istemci "henüz denenmedi" gösterebilir).
--   * get_public_profile, künye ile ilgili hiçbir alanı (display_name,
--     yaş, meslek, niyet) döndürmez — bunlar yalnızca reveal_identity()
--     üzerinden gelir. Yalnızca username, şehir adı, onaylanmış
--     fotoğraflar ve çözülme oranı döner.
--   * Gizlenmiş (3 ay) veya atlanmış bir profil get_public_profile ile
--     hâlâ görülebilir — bu iki durum yalnızca discover_profiles'ın akış
--     listesinden çıkarır, doğrudan erişimi (Atlananlar ekranından)
--     engellemez. Asıl kilit start_quiz'de zaten var.

create or replace function public.get_public_profile(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id   uuid := (select auth.uid());
  v_profile     record;
  v_photos      jsonb;
  v_solve_rate  numeric;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select p.id, p.username, c.name as city_name
    into v_profile
    from public.profiles p
    join public.cities c on c.id = p.city_id
    where p.id = p_profile_id and p.status = 'published';

  if not found then
    raise exception 'Profil bulunamadı veya yayınlanmamış';
  end if;

  if exists (
    select 1 from public.blocks
    where (blocker_id = v_viewer_id and blocked_id = p_profile_id)
       or (blocker_id = p_profile_id and blocked_id = v_viewer_id)
  ) then
    raise exception 'Bu profille etkileşim engellenmiş';
  end if;

  select jsonb_agg(
           jsonb_build_object('id', ph.id, 'position', ph.position, 'storage_path', ph.storage_path)
           order by ph.position
         )
    into v_photos
    from public.photos ph
    where ph.profile_id = p_profile_id and ph.moderation_status = 'approved';

  select case
           when count(*) filter (where qa.status in ('completed', 'failed_checkpoint')) = 0 then null
           else round(
             100.0 * count(*) filter (where qa.unlocked_tier > 0)
             / count(*) filter (where qa.status in ('completed', 'failed_checkpoint'))
           )
         end
    into v_solve_rate
    from public.quiz_attempts qa
    where qa.target_profile_id = p_profile_id;

  return jsonb_build_object(
    'id', v_profile.id,
    'username', v_profile.username,
    'city', v_profile.city_name,
    'photos', coalesce(v_photos, '[]'::jsonb),
    'solve_rate', v_solve_rate
  );
end;
$$;

revoke execute on function public.get_public_profile(uuid) from public;
grant execute on function public.get_public_profile(uuid) to authenticated;

-- =========================================================================
-- discover_profiles
-- =========================================================================
create or replace function public.discover_profiles(p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id     uuid := (select auth.uid());
  v_viewer_city   int;
  v_calls_used    int;
  v_result        jsonb;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select city_id into v_viewer_city from public.profiles where id = v_viewer_id;
  if v_viewer_city is null then
    raise exception 'Profilin bulunamadı';
  end if;

  select discover_calls_used into v_calls_used
    from public.daily_quotas
    where user_id = v_viewer_id and date = current_date;
  if coalesce(v_calls_used, 0) >= 200 then
    raise exception 'Günlük keşif çağrı kotan doldu';
  end if;

  insert into public.daily_quotas as dq (user_id, date, discover_calls_used)
    values (v_viewer_id, current_date, 1)
    on conflict (user_id, date)
    do update set discover_calls_used = dq.discover_calls_used + 1;

  select jsonb_agg(
           jsonb_build_object(
             'id', p.id,
             'username', p.username,
             'cover_photo', (
               select ph.storage_path from public.photos ph
               where ph.profile_id = p.id and ph.position = 1 and ph.moderation_status = 'approved'
             ),
             'photo_count', (
               select count(*) from public.photos ph2
               where ph2.profile_id = p.id and ph2.moderation_status = 'approved'
             ),
             'solve_rate', (
               select case
                        when count(*) filter (where qa.status in ('completed', 'failed_checkpoint')) = 0 then null
                        else round(
                          100.0 * count(*) filter (where qa.unlocked_tier > 0)
                          / count(*) filter (where qa.status in ('completed', 'failed_checkpoint'))
                        )
                      end
               from public.quiz_attempts qa
               where qa.target_profile_id = p.id
             )
           ) order by random()
         )
    into v_result
    from public.profiles p
    where p.id <> v_viewer_id
      and p.status = 'published'
      and p.city_id = v_viewer_city
      and p.username is not null
      and exists (
        select 1 from public.photos ph3
        where ph3.profile_id = p.id and ph3.position = 1 and ph3.moderation_status = 'approved'
      )
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = v_viewer_id and b.blocked_id = p.id)
           or (b.blocker_id = p.id and b.blocked_id = v_viewer_id)
      )
      and not exists (
        select 1 from public.hidden_profiles h
        where h.viewer_id = v_viewer_id and h.target_profile_id = p.id and h.hidden_until > now()
      )
      and not exists (
        select 1 from public.skipped_profiles s
        where s.viewer_id = v_viewer_id and s.target_profile_id = p.id
      )
      and not exists (
        select 1 from public.quiz_attempts qa2
        where qa2.viewer_id = v_viewer_id and qa2.target_profile_id = p.id
      )
    limit p_limit;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

revoke execute on function public.discover_profiles(int) from public;
grant execute on function public.discover_profiles(int) to authenticated;

-- =========================================================================
-- skip_profile / unskip_profile
-- =========================================================================
create or replace function public.skip_profile(p_target_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  if v_viewer_id = p_target_profile_id then
    raise exception 'Kendini atlayamazsın';
  end if;

  insert into public.skipped_profiles (viewer_id, target_profile_id)
    values (v_viewer_id, p_target_profile_id)
    on conflict (viewer_id, target_profile_id) do update set skipped_at = now();
end;
$$;

create or replace function public.unskip_profile(p_target_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  delete from public.skipped_profiles
    where viewer_id = v_viewer_id and target_profile_id = p_target_profile_id;
end;
$$;

revoke execute on function public.skip_profile(uuid) from public;
revoke execute on function public.unskip_profile(uuid) from public;
grant execute on function public.skip_profile(uuid) to authenticated;
grant execute on function public.unskip_profile(uuid) to authenticated;
