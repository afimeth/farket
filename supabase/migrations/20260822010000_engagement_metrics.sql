-- Farket — Faz A: etkileşim ölçüm altyapısı (22 Ağustos).
--
-- Gerekçe: uygulama yoğun şekilde oyunlaştırılmış (ödül merdiveni, günlük hak,
-- gizlenme cezası, ikinci şans) ama hiçbiri ÖLÇÜLMÜYOR. Hangi mekaniğin işe
-- yaradığı, huninin nerede tıkandığı, cezalandırılan kullanıcının geri dönüp
-- dönmediği bilinmiyor. Bu migration yeni bir kullanıcı davranışı EKLEMEZ;
-- yalnızca mevcut tablolardan türetilen operasyon sorgularını isimlendirir.
--
-- Yeni tablo/kolon yok: quiz_attempts, messages, conversations, daily_quotas ve
-- hidden_profiles zaten gereken her şeyi taşıyor. Ayrı bir olay (event) tablosu
-- kasıtlı olarak eklenmedi — yazma yükü ve kişisel veri yüzeyi getirirdi.
--
-- GÜVENLİK: üçü de security definer ama HİÇBİR role GRANT VERİLMEZ —
-- purge_deleted_accounts / expire_pending_conversations / release_stale_hides
-- ile birebir aynı desen: EXECUTE yalnızca `postgres` sahibinde kalır, yani
-- doğrudan psql ya da pg_cron çalıştırabilir. service_role bile çağıramaz;
-- bu kasıtlı, çünkü metrikler ürün yüzeyi değil operasyon aracı.
-- Hiçbiri kişiye indirgenebilir veri döndürmez, yalnızca sayı/oran
-- toplulaştırması yapar (KVKK yüzeyi yok).
--
-- BOT'LAR HARİÇ: profiles.is_bot = true olan tohum hesaplar tüm sayımların
-- dışında; aksi halde huni ve kohort sayıları yapay olarak şişerdi. Silinmiş
-- hesaplar (deleted_at) ise DAHİL — onlar gerçek kullanıcıydı, hariç tutmak
-- tutundurma oranını olduğundan iyi gösterirdi.

-- =========================================================================
-- 0) _pct — payda 0/null iken hata yerine null döndüren yüzde yardımcısı.
-- Huninin ilk adımı boşken (henüz veri yok) fonksiyonun patlamaması için.
-- =========================================================================
create or replace function public._pct(p_num bigint, p_den bigint)
returns numeric
language sql
immutable
as $$
  select case
           when coalesce(p_den, 0) = 0 then null
           else round(100.0 * coalesce(p_num, 0) / p_den, 1)
         end;
$$;

revoke execute on function public._pct(bigint, bigint) from public;

comment on function public._pct(bigint, bigint) is
  'Dahili: sıfır paydaya karşı güvenli yüzde. Yalnızca ölçüm fonksiyonları kullanır.';

-- =========================================================================
-- 1) _activity_days — "bir kullanıcı hangi günlerde aktifti" tek kaynağı.
-- Üç sinyalin birleşimi: quiz denemesi başlatmak, mesaj göndermek, kota
-- tüketen bir işlem yapmak (daily_quotas satırı). Dahili yardımcı, hiçbir
-- role EXECUTE verilmez.
-- =========================================================================
create or replace function public._activity_days(p_since date)
returns table (user_id uuid, day date)
language sql
stable
security definer
set search_path = public
as $$
  select qa.viewer_id, (qa.started_at at time zone 'utc')::date
    from public.quiz_attempts qa
   where (qa.started_at at time zone 'utc')::date >= p_since
  union
  select m.sender_id, (m.created_at at time zone 'utc')::date
    from public.messages m
   where (m.created_at at time zone 'utc')::date >= p_since
  union
  select dq.user_id, dq.date
    from public.daily_quotas dq
   where dq.date >= p_since;
$$;

revoke execute on function public._activity_days(date) from public;

comment on function public._activity_days(date) is
  'Dahili: kullanıcı-gün aktiflik birleşimi (quiz başlatma, mesaj, kota tüketimi). Yalnızca ölçüm fonksiyonları kullanır.';

-- =========================================================================
-- 2) get_engagement_funnel — keşiften bağlantıya kadar adım adım dönüşüm.
--
-- Son adım "bağlantı" tanımı get_my_connections ile BİREBİR aynı: sohbette
-- iki tarafın da en az bir mesajı olması. Tanım iki yerde tekrarlandığı için
-- biri değişirse diğeri de değişmeli (get_my_connections'daki having bloğu).
--
-- 'rate' alanı bir önceki adıma göre yüzde; ilk adımda null.
-- =========================================================================
create or replace function public.get_engagement_funnel(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_since        timestamptz := now() - make_interval(days => p_days);
  v_deck         bigint;
  v_started      bigint;
  v_checkpoint   bigint;
  v_unlocked     bigint;
  v_requested    bigint;
  v_accepted     bigint;
  v_connected    bigint;

  v_failed       bigint;
  v_returned     bigint;
  v_avg_days     numeric;
begin
  select coalesce(sum(dq.deck_profiles_served), 0) into v_deck
    from public.daily_quotas dq
    join public.profiles p on p.id = dq.user_id
   where dq.date >= v_since::date
     and not coalesce(p.is_bot, false);

  select count(*),
         count(*) filter (where qa.checkpoint_passed),
         count(*) filter (where qa.unlocked_tier > 0)
    into v_started, v_checkpoint, v_unlocked
    from public.quiz_attempts qa
    join public.profiles p on p.id = qa.viewer_id
   where qa.started_at >= v_since
     and not coalesce(p.is_bot, false);

  select count(*),
         count(*) filter (where c.status = 'accepted')
    into v_requested, v_accepted
    from public.conversations c
    join public.profiles p on p.id = c.participant_a
   where c.created_at >= v_since
     and not coalesce(p.is_bot, false);

  select count(*) into v_connected
    from (
      select c.id
        from public.conversations c
        join public.messages m on m.conversation_id = c.id
       where c.created_at >= v_since
       group by c.id, c.participant_a, c.participant_b
      having count(*) filter (where m.sender_id = c.participant_a) > 0
         and count(*) filter (where m.sender_id = c.participant_b) > 0
    ) x;

  -- Ceza sonrası dönüş (Faz C telafi mekaniğinin temel çizgisi).
  -- "Başarısız 1. deneme" = ara kontrolde elenen ya da 7 doğruya ulaşamayan.
  select count(*),
         count(*) filter (where a2.id is not null),
         avg(extract(epoch from (a2.started_at - a1.completed_at)) / 86400.0)
    into v_failed, v_returned, v_avg_days
    from public.quiz_attempts a1
    join public.profiles p on p.id = a1.viewer_id
    left join public.quiz_attempts a2
      on a2.viewer_id = a1.viewer_id
     and a2.target_profile_id = a1.target_profile_id
     and a2.attempt_no = 2
   where a1.attempt_no = 1
     and a1.completed_at is not null
     and a1.completed_at >= v_since
     and a1.unlocked_tier = 0
     and not coalesce(p.is_bot, false);

  return jsonb_build_object(
    'window_days', p_days,
    'generated_at', now(),
    'funnel', jsonb_build_array(
      jsonb_build_object('step', 'deck_served',     'count', v_deck,       'rate', null),
      jsonb_build_object('step', 'quiz_started',    'count', v_started,    'rate', public._pct(v_started,    v_deck)),
      jsonb_build_object('step', 'checkpoint_pass', 'count', v_checkpoint, 'rate', public._pct(v_checkpoint, v_started)),
      jsonb_build_object('step', 'tier_unlocked',   'count', v_unlocked,   'rate', public._pct(v_unlocked,   v_checkpoint)),
      jsonb_build_object('step', 'message_request', 'count', v_requested,  'rate', public._pct(v_requested,  v_unlocked)),
      jsonb_build_object('step', 'request_accepted','count', v_accepted,   'rate', public._pct(v_accepted,   v_requested)),
      jsonb_build_object('step', 'connection',      'count', v_connected,  'rate', public._pct(v_connected,  v_accepted))
    ),
    'penalty_recovery', jsonb_build_object(
      'failed_first_attempts', v_failed,
      'returned_for_retry', v_returned,
      'return_rate', public._pct(v_returned, v_failed),
      'avg_days_to_return', round(coalesce(v_avg_days, 0)::numeric, 1)
    )
  );
end;
$$;

revoke execute on function public.get_engagement_funnel(int) from public;

comment on function public.get_engagement_funnel(int) is
  'Operasyon metriği: keşif -> quiz -> checkpoint -> tier -> mesaj -> kabul -> bağlantı dönüşüm hunisi + ceza sonrası dönüş oranı. Yalnızca postgres (psql/pg_cron).';

-- =========================================================================
-- 3) get_retention_cohorts — haftalık kayıt kohortlarının D1/D7/D30'u.
--
-- TANIMLAR (düşük hacimde tek-gün ölçümü çok gürültülü olduğu için pencere
-- tabanlı "geri döndü mü" tanımı seçildi):
--   d1  : kayıttan sonraki 1. günde aktif
--   d7  : 1.-7. günler arasında en az bir gün aktif
--   d30 : 1.-30. günler arasında en az bir gün aktif
-- Kohort o pencereyi henüz doldurmadıysa ilgili alan null döner (payda
-- eksik olduğu için oranı raporlamak yanıltıcı olurdu).
-- =========================================================================
create or replace function public.get_retention_cohorts(p_weeks int default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_since  date := (now() - make_interval(weeks => p_weeks))::date;
  v_result jsonb;
begin
  with cohort_users as (
    select p.id,
           (p.created_at at time zone 'utc')::date as signup_day,
           date_trunc('week', p.created_at at time zone 'utc')::date as cohort_week
      from public.profiles p
     where (p.created_at at time zone 'utc')::date >= v_since
       and not coalesce(p.is_bot, false)
  ),
  acts as (
    select a.user_id, a.day from public._activity_days(v_since) a
  ),
  flags as (
    select cu.cohort_week,
           cu.id,
           bool_or(ac.day = cu.signup_day + 1)                          as d1,
           bool_or(ac.day between cu.signup_day + 1 and cu.signup_day + 7)  as d7,
           bool_or(ac.day between cu.signup_day + 1 and cu.signup_day + 30) as d30,
           max(cu.signup_day) as signup_day
      from cohort_users cu
      left join acts ac on ac.user_id = cu.id
     group by cu.cohort_week, cu.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'cohort_week', f.cohort_week,
           'size', f.size,
           'd1', f.d1_rate,
           'd7', f.d7_rate,
           'd30', f.d30_rate
         ) order by f.cohort_week desc), '[]'::jsonb)
    into v_result
    from (
      select cohort_week,
             count(*) as size,
             case when max(signup_day) + 1  <= current_date
                  then public._pct(count(*) filter (where d1),  count(*)) end as d1_rate,
             case when max(signup_day) + 7  <= current_date
                  then public._pct(count(*) filter (where d7),  count(*)) end as d7_rate,
             case when max(signup_day) + 30 <= current_date
                  then public._pct(count(*) filter (where d30), count(*)) end as d30_rate
        from flags
       group by cohort_week
    ) f;

  return jsonb_build_object(
    'weeks', p_weeks,
    'generated_at', now(),
    'note', 'd1: kayıt+1. gün aktif. d7/d30: 1.-7. / 1.-30. günler arasında en az bir gün aktif. Pencere dolmadıysa null.',
    'cohorts', v_result
  );
end;
$$;

revoke execute on function public.get_retention_cohorts(int) from public;

comment on function public.get_retention_cohorts(int) is
  'Operasyon metriği: haftalık kayıt kohortlarının D1/D7/D30 tutundurma oranı. Yalnızca postgres (psql/pg_cron).';

-- =========================================================================
-- 4) get_core_action_daily — gün bazında çekirdek aksiyon frekansı.
-- "Bağlantı kuruldu" günü = geç kalan tarafın ilk mesajının günü, yani
-- karşılıklılığın sağlandığı an (get_my_connections'daki connected_at ile
-- aynı tanım).
-- =========================================================================
create or replace function public.get_core_action_daily(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_since  date := (now() - make_interval(days => p_days))::date;
  v_result jsonb;
begin
  with days as (
    select generate_series(v_since, current_date, interval '1 day')::date as day
  ),
  quizzes as (
    select (qa.started_at at time zone 'utc')::date as day,
           count(*) as started,
           count(*) filter (where qa.status = 'completed') as completed
      from public.quiz_attempts qa
      join public.profiles p on p.id = qa.viewer_id
     where (qa.started_at at time zone 'utc')::date >= v_since
       and not coalesce(p.is_bot, false)
     group by 1
  ),
  msgs as (
    select (m.created_at at time zone 'utc')::date as day, count(*) as sent
      from public.messages m
      join public.profiles p on p.id = m.sender_id
     where (m.created_at at time zone 'utc')::date >= v_since
       and not coalesce(p.is_bot, false)
     group by 1
  ),
  conns as (
    select (x.connected_at at time zone 'utc')::date as day, count(*) as formed
      from (
        select greatest(
                 min(m.created_at) filter (where m.sender_id = c.participant_a),
                 min(m.created_at) filter (where m.sender_id = c.participant_b)
               ) as connected_at
          from public.conversations c
          join public.messages m on m.conversation_id = c.id
         group by c.id, c.participant_a, c.participant_b
        having count(*) filter (where m.sender_id = c.participant_a) > 0
           and count(*) filter (where m.sender_id = c.participant_b) > 0
      ) x
     where (x.connected_at at time zone 'utc')::date >= v_since
     group by 1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'day', d.day,
           'quiz_started', coalesce(q.started, 0),
           'quiz_completed', coalesce(q.completed, 0),
           'messages_sent', coalesce(mm.sent, 0),
           'connections_formed', coalesce(cc.formed, 0)
         ) order by d.day), '[]'::jsonb)
    into v_result
    from days d
    left join quizzes q on q.day = d.day
    left join msgs   mm on mm.day = d.day
    left join conns  cc on cc.day = d.day;

  return jsonb_build_object('days', p_days, 'generated_at', now(), 'series', v_result);
end;
$$;

revoke execute on function public.get_core_action_daily(int) from public;

comment on function public.get_core_action_daily(int) is
  'Operasyon metriği: gün bazında quiz başlatma/tamamlama, gönderilen mesaj, kurulan bağlantı. Yalnızca postgres (psql/pg_cron).';
