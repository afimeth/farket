-- Discovery pager card needs a swipeable multi-photo view with a position indicator,
-- but discover_profiles only ever returned a single cover thumb. Add an ordered
-- thumb-path array (capped at 6) alongside the existing cover_photo_thumb/photo_count
-- fields. Everything else in this CREATE OR REPLACE is copied verbatim from the
-- previous latest definition (20260818112446_v41_quiz_allowance.sql) — only the new
-- 'photos' key was inserted into the jsonb_build_object.

create or replace function public.discover_profiles(p_limit int default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id     uuid := (select auth.uid());
  v_viewer_city   int;
  v_deck_limit    int;
  v_served        int;
  v_remaining     int;
  v_effective_limit int;
  v_result        jsonb;
  v_served_now    int;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select city_id into v_viewer_city from public.profiles where id = v_viewer_id;
  if v_viewer_city is null then
    raise exception 'Profilin bulunamadı';
  end if;

  select value::int into v_deck_limit from public.app_settings where key = 'daily_deck_limit';

  select deck_profiles_served into v_served
    from public.daily_quotas
    where user_id = v_viewer_id and date = current_date;
  v_served := coalesce(v_served, 0);

  if v_served >= v_deck_limit then
    raise exception 'Günlük deste sınırına ulaştın';
  end if;

  v_remaining := v_deck_limit - v_served;
  v_effective_limit := least(p_limit, v_remaining);

  insert into public.daily_quotas as dq (user_id, date, discover_calls_used)
    values (v_viewer_id, current_date, 1)
    on conflict (user_id, date)
    do update set discover_calls_used = dq.discover_calls_used + 1;

  select jsonb_agg(
           jsonb_build_object(
             'id', p.id,
             'username', p.username,
             'cover_photo_thumb', (
               select ph.storage_path_thumb from public.photos ph
               where ph.profile_id = p.id and ph.position = 1 and ph.moderation_status = 'approved'
             ),
             'photo_count', (
               select count(*) from public.photos ph2
               where ph2.profile_id = p.id and ph2.moderation_status = 'approved'
             ),
             'photos', (
               select coalesce(jsonb_agg(ph4.storage_path_thumb order by ph4.position), '[]'::jsonb)
               from (
                 select storage_path_thumb, position from public.photos
                 where profile_id = p.id and moderation_status = 'approved'
                 order by position
                 limit 6
               ) ph4
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
        where h.viewer_id = v_viewer_id and h.target_profile_id = p.id
          and (h.retry_used or h.available_at > now())
      )
      and not exists (
        select 1 from public.skipped_profiles s
        where s.viewer_id = v_viewer_id and s.target_profile_id = p.id
      )
      and not exists (
        select 1 from public.quiz_attempts qa2
        where qa2.viewer_id = v_viewer_id and qa2.target_profile_id = p.id
      )
    limit v_effective_limit;

  v_result := coalesce(v_result, '[]'::jsonb);
  v_served_now := jsonb_array_length(v_result);

  update public.daily_quotas
    set deck_profiles_served = deck_profiles_served + v_served_now
    where user_id = v_viewer_id and date = current_date;

  return v_result;
end;
$$;
