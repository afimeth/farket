-- Farket v4.1 — sonraki fazlar, Faz 5/6: get_quiz_radar + get_weekly_digest.
--
-- İkisi de yalnızca ÇAĞIRANIN KENDİ profili için çalışır (parametre
-- almaz, auth.uid() üzerinden) — başka bir profilin performans verisini
-- görmek mümkün değil, bu tamamen kendi profilini iyileştirmek isteyen
-- kullanıcı için bir araç.

-- =========================================================================
-- 1) get_quiz_radar — kendi kalıp sorularının soru bazlı performansı.
-- "Ölü soru" işareti, get_quiz_allowance'daki aynı basitleştirilmiş
-- sinyali (question_templates.is_active) kullanıyor — v4.1'in "30+
-- gösterimde <%5 doğru" tanımı ayrı bir agregasyon gerektiriyordu,
-- bkz. Migration 5 yorumu.
-- =========================================================================
create or replace function public.get_quiz_radar()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'template_id', x.template_id,
           'body', x.body,
           'shown_count', x.shown_count,
           'correct_rate', x.correct_rate,
           'is_dead', x.is_dead
         ) order by x.shown_count desc), '[]'::jsonb)
    into v_result
    from (
      select qt.id as template_id, qt.body,
             count(aa.*) as shown_count,
             round(100.0 * count(*) filter (where aa.is_correct) / nullif(count(aa.*), 0)) as correct_rate,
             not qt.is_active as is_dead
      from public.attempt_questions aq
      join public.quiz_attempts qa on qa.id = aq.attempt_id
      join public.question_templates qt on qt.id = aq.template_id
      left join public.attempt_answers aa
        on aa.attempt_id = aq.attempt_id and aa.question_position = aq.position
      where qa.target_profile_id = v_uid and aq.template_id is not null
      group by qt.id, qt.body, qt.is_active
    ) x;

  return v_result;
end;
$$;

revoke execute on function public.get_quiz_radar() from public;
grant execute on function public.get_quiz_radar() to authenticated;

-- =========================================================================
-- 2) get_weekly_digest — son 7 gün: kaç deneme, kaçı geçti, en çok
-- hangi soruda takıldılar.
-- =========================================================================
create or replace function public.get_weekly_digest()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid             uuid := (select auth.uid());
  v_attempts_count  int;
  v_passed_count    int;
  v_hardest         record;
  v_result          jsonb;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select count(*), count(*) filter (where unlocked_tier > 0)
    into v_attempts_count, v_passed_count
    from public.quiz_attempts
    where target_profile_id = v_uid and started_at >= now() - interval '7 days';

  select qt.body as body, count(*) as miss_count
    into v_hardest
    from public.attempt_questions aq
    join public.quiz_attempts qa on qa.id = aq.attempt_id
    join public.attempt_answers aa on aa.attempt_id = aq.attempt_id and aa.question_position = aq.position
    join public.question_templates qt on qt.id = aq.template_id
    where qa.target_profile_id = v_uid
      and qa.started_at >= now() - interval '7 days'
      and not aa.is_correct
    group by qt.id, qt.body
    order by count(*) desc
    limit 1;

  v_result := jsonb_build_object(
    'attempts_count', coalesce(v_attempts_count, 0),
    'passed_count', coalesce(v_passed_count, 0),
    'hardest_question', case
      when v_hardest.body is not null
      then jsonb_build_object('body', v_hardest.body, 'miss_count', v_hardest.miss_count)
      else null
    end
  );

  return v_result;
end;
$$;

revoke execute on function public.get_weekly_digest() from public;
grant execute on function public.get_weekly_digest() to authenticated;
