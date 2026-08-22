-- Farket — Faz C: telafi mekaniği + ilerleme paylaşımı rızası (22 Ağustos).
--
-- 1) TELAFİ. Uygulama cezalandırıyor ama onarım yolu sunmuyordu: quiz'i
--    kaybedince profil 3 (ara kontrol) ya da 3/14 gün (düşük skor) gizleniyor,
--    profil başına ömürlük 2 deneme hakkı var, arada yapılabilecek hiçbir şey
--    yok. Cezanın telafisi olmayan döngü alışkanlık değil zorlama üretir.
--
--    ÖLÇÜLÜ ÇÖZÜM — cezanın kendisi DEĞİŞMİYOR: 3/14 günlük süreler, retry_cost
--    (2/3/5 kredi), ömürlük 2 deneme sınırı ve ikinci denemede max_tier=8
--    aynen duruyor. Eklenen tek şey: haftada bir kez, bir profil için BEKLEMEYİ
--    erken bitirebilme hakkı. Kredi yine ödenir (start_retry'de), tavan yine 8.
--
--    hidden_profiles.released_early kolonu zaten vardı ama yalnızca sistem
--    tarafı (release_stale_hides, deste arzı düşünce) kullanıyordu; artık
--    kullanıcının kendi iradesiyle de tetiklenebiliyor.
--
--    Şimdilik TEK telafi mekaniği. "Profilini güçlendirince bekleme kısalsın"
--    gibi ikinci bir yol, bunun ceza-sonrası-dönüş oranına etkisi ölçüldükten
--    SONRA değerlendirilecek (bkz. METRIKLER.md) — ikisini birlikte açmak
--    hangisinin işe yaradığını ölçülemez kılardı.
--
-- 2) RIZA. quiz_progress bildirimi, quiz'i ÇÖZEN kişinin rızası olmadan hedefe
--    "şu an 6. soruda, 4 doğru" diye canlı yayın yapıyor. Varsayılan davranış
--    değişmiyor (bayrak default true) ama artık kapatılabiliyor.

-- =========================================================================
-- 1) profiles — iki yeni kolon.
-- `revoke update on public.profiles from authenticated` yürürlükte olduğu
-- için ikisi de yalnızca RPC üzerinden yazılabilir.
-- =========================================================================
alter table public.profiles
  add column last_early_retry_at   timestamptz,
  add column share_quiz_progress   boolean not null default true;

comment on column public.profiles.last_early_retry_at is
  'Son "erken ikinci şans" kullanımı. Haftada bir hakkın sayacı; daily_quotas günlük olduğu için orada tutulamaz.';
comment on column public.profiles.share_quiz_progress is
  'Kullanıcı başkalarının quizini çözerken canlı ilerlemesinin profil sahibine bildirilmesine izin veriyor mu.';

-- =========================================================================
-- 2) redeem_early_retry — haftada bir kez beklemeyi erken bitir.
--
-- Cezayı kaldırmaz, yalnızca available_at'i öne çeker. retry_used false
-- kalır ki kullanıcı start_retry'yi normal akışta (kredisini ödeyerek)
-- çağırabilsin.
-- =========================================================================
create or replace function public.redeem_early_retry(p_target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_hide      record;
  v_last      timestamptz;
  v_next_at   timestamptz;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  if p_target_profile_id is null then
    raise exception 'Hangi profil için kullanacağını seçmedin';
  end if;

  -- Kendi satırını kilitle: aynı hakkın iki eşzamanlı istekle iki kez
  -- harcanmasını engeller.
  perform 1 from public.profiles where id = v_uid for update;

  select last_early_retry_at into v_last
    from public.profiles where id = v_uid;

  if v_last is not null and now() - v_last < interval '7 days' then
    v_next_at := v_last + interval '7 days';
    raise exception 'Erken ikinci şans hakkını bu hafta kullandın. Yeniden kullanabileceğin tarih: %',
      to_char(v_next_at at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI');
  end if;

  select * into v_hide
    from public.hidden_profiles
    where viewer_id = v_uid and target_profile_id = p_target_profile_id
    for update;

  if not found then
    raise exception 'Bu profil için bekleme süren yok';
  end if;

  if v_hide.retry_used then
    raise exception 'Bu profil için ikinci şansını zaten kullandın';
  end if;

  if v_hide.available_at <= now() then
    raise exception 'Bu profili zaten tekrar deneyebilirsin, hak harcamana gerek yok';
  end if;

  update public.hidden_profiles
    set available_at = now(),
        released_early = true
    where viewer_id = v_uid and target_profile_id = p_target_profile_id;

  update public.profiles
    set last_early_retry_at = now()
    where id = v_uid;

  return jsonb_build_object(
    'available_now', true,
    'retry_cost', v_hide.retry_cost,
    'next_redeem_at', now() + interval '7 days'
  );
end;
$$;

revoke execute on function public.redeem_early_retry(uuid) from public;
grant execute on function public.redeem_early_retry(uuid) to authenticated;

comment on function public.redeem_early_retry(uuid) is
  'Haftada bir kez, bir profilin ikinci deneme beklemesini erken bitirir. Cezayı kaldırmaz: retry_cost ve max_tier=8 aynen geçerli.';

-- =========================================================================
-- 3) get_early_retry_status — istemcinin butonu doğru göstermesi için.
-- =========================================================================
create or replace function public.get_early_retry_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_last timestamptz;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select last_early_retry_at into v_last from public.profiles where id = v_uid;

  return jsonb_build_object(
    'available', v_last is null or now() - v_last >= interval '7 days',
    'last_used_at', v_last,
    'next_available_at', case when v_last is null then null else v_last + interval '7 days' end
  );
end;
$$;

revoke execute on function public.get_early_retry_status() from public;
grant execute on function public.get_early_retry_status() to authenticated;

comment on function public.get_early_retry_status() is
  'Erken ikinci şans hakkı şu an kullanılabilir mi, değilse ne zaman yenilenir.';

-- =========================================================================
-- 3b) get_my_pending_retries — beklemedeki profillerin listesi.
--
-- Bu OLMADAN telafi mekaniği erişilemez kalırdı: discover_profiles gizlenmiş
-- profilleri desteden tamamen çıkarıyor (`h.available_at > now()` filtresi),
-- yani kullanıcı beklediği profili hiçbir ekranda görmüyor ve üzerinde
-- redeem_early_retry çağıracak bir yer bulamıyordu.
--
-- get_blocked_users / get_my_connections ile aynı desen: profiles üzerindeki
-- tek select politikası "yalnızca kendi profilin" olduğu için karşı tarafın
-- username'i ancak SECURITY DEFINER bir RPC ile döndürülebiliyor.
-- =========================================================================
create or replace function public.get_my_pending_retries()
returns table (
  profile_id           uuid,
  username             text,
  first_attempt_score  int,
  available_at         timestamptz,
  retry_cost           int,
  released_early       boolean
)
language plpgsql
stable
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
    select p.id, p.username, h.first_attempt_score, h.available_at, h.retry_cost, h.released_early
      from public.hidden_profiles h
      join public.profiles p on p.id = h.target_profile_id
     where h.viewer_id = v_uid
       and not h.retry_used
       and p.status = 'published'
       -- Engellenen taraf listede görünmez (get_my_connections ile aynı kural).
       and not exists (
         select 1 from public.blocks b
         where (b.blocker_id = v_uid and b.blocked_id = p.id)
            or (b.blocker_id = p.id and b.blocked_id = v_uid)
       )
     order by h.available_at;
end;
$$;

revoke execute on function public.get_my_pending_retries() from public;
grant execute on function public.get_my_pending_retries() to authenticated;

comment on function public.get_my_pending_retries() is
  'İkinci deneme hakkı duran, bekleme süresi dolmuş ya da dolmamış profiller. Telafi mekaniğinin (redeem_early_retry) giriş noktası.';

-- =========================================================================
-- 4) _notify_progress — çözen kişinin rızası yoksa ilerleme bildirimi yok.
--
-- Bayrak ÇÖZEN kişide (quiz_attempts.viewer_id) kontrol ediliyor, bildirimi
-- ALAN kişide değil: paylaşılan veri çözenin davranışı, dolayısıyla rıza da
-- onun. near_miss ve quiz_passed ETKİLENMEZ — onlar tamamlanmış, somut ve
-- alıcı için aksiyona açık olaylar; canlı takip değil.
-- =========================================================================
create or replace function public._notify_progress(
  p_user_id     uuid,
  p_attempt_id  uuid,
  p_position    int,
  p_score       int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_id  uuid;
  v_new_id  uuid;
  v_shares  boolean;
begin
  select p.share_quiz_progress into v_shares
    from public.quiz_attempts qa
    join public.profiles p on p.id = qa.viewer_id
    where qa.id = p_attempt_id;

  if not coalesce(v_shares, true) then
    return;
  end if;

  select id into v_old_id
    from public.notifications
    where user_id = p_user_id and type = 'quiz_progress' and attempt_id = p_attempt_id and superseded_by is null
    order by created_at desc
    limit 1;

  insert into public.notifications (user_id, type, attempt_id, payload, progress_current, progress_score)
    values (p_user_id, 'quiz_progress', p_attempt_id, '{}'::jsonb, p_position, p_score)
    returning id into v_new_id;

  if v_old_id is not null then
    update public.notifications set superseded_by = v_new_id where id = v_old_id;
  end if;
end;
$$;

revoke execute on function public._notify_progress(uuid, uuid, int, int) from public;

-- =========================================================================
-- 5) set_share_quiz_progress — ayarlardaki anahtar.
-- =========================================================================
create or replace function public.set_share_quiz_progress(p_value boolean)
returns void
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
  if p_value is null then
    raise exception 'Geçersiz değer';
  end if;

  update public.profiles set share_quiz_progress = p_value where id = v_uid;
end;
$$;

revoke execute on function public.set_share_quiz_progress(boolean) from public;
grant execute on function public.set_share_quiz_progress(boolean) to authenticated;

comment on function public.set_share_quiz_progress(boolean) is
  'Quiz çözerken canlı ilerlemenin profil sahibine bildirilmesini aç/kapat. Varsayılan açık.';

-- =========================================================================
-- 6) get_my_privacy_settings — ayarlar ekranının anahtarı doğru göstermesi
-- için. profiles üzerindeki select politikası zaten "yalnızca kendi profilin"
-- ama istemci tek kolon için tablo sorgulamak yerine bunu çağırsın diye
-- (ileride başka gizlilik anahtarları da buraya eklenecek).
-- =========================================================================
create or replace function public.get_my_privacy_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid    uuid := (select auth.uid());
  v_shares boolean;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select share_quiz_progress into v_shares from public.profiles where id = v_uid;

  return jsonb_build_object('share_quiz_progress', coalesce(v_shares, true));
end;
$$;

revoke execute on function public.get_my_privacy_settings() from public;
grant execute on function public.get_my_privacy_settings() to authenticated;
