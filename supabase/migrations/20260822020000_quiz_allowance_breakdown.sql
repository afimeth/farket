-- Farket — Faz B: günlük quiz hakkının görünür kılınması (22 Ağustos).
--
-- get_quiz_allowance beş koşullu güzel bir ustalık merdiveni (taban 3, her
-- kazanılan koşul +1, tavan 7) ama kullanıcıya TAMAMEN GÖRÜNMEZ: bugün neden
-- 5 hakkı olduğunu, 6.'yı nasıl kazanacağını bilmiyor. Görünmeyen ilerleme
-- ilerleme değildir. Bu migration YENİ MEKANİK EKLEMEZ — var olan hesabı
-- kullanıcıya okunabilir hale getirir.
--
-- TEK KAYNAK: mantık kopyalanmıyor. Breakdown asıl hesap oluyor,
-- get_quiz_allowance onu çağırıp toplamı döndürüyor. Böylece iki hesap
-- zamanla birbirinden ayrışamaz (yoksa biri güncellenip diğeri unutulur ve
-- panel yalan söylemeye başlar — playbook'un "misleading progress indicator"
-- maddesi tam olarak bu).
--
-- İmza ve yetki kontrolü korunuyor: get_quiz_allowance(uuid) hâlâ yalnızca
-- p_user_id = auth.uid() için çalışıyor, start_quiz / start_retry çağrıları
-- olduğu gibi geçerli.

-- =========================================================================
-- 1) get_quiz_allowance_breakdown — koşul koşul döküm.
--
-- Koşullar (hepsi eski get_quiz_allowance gövdesinden birebir taşındı):
--   verified          profil doğrulanmış (profiles.verified_at)
--   no_pending_request cevap bekleyen mesaj isteği yok
--   quiz_health       kendi sorularının hiçbiri otomatik pasife düşmemiş VE
--                     genel çözülme oranı %10-85 aralığında
--   profile_complete  7 fotoğraf + en az 5 aktif serbest soru + gizli kart
-- =========================================================================
create or replace function public.get_quiz_allowance_breakdown()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid              uuid := (select auth.uid());
  v_base             int := 3;
  v_cap              int := 7;
  v_verified         boolean;
  v_no_pending       boolean;
  v_no_dead_question boolean;
  v_solve_rate       numeric;
  v_quiz_health      boolean;
  v_photo_count      int;
  v_custom_count     int;
  v_secret_card_ok   boolean;
  v_profile_complete boolean;
  v_earned           int;
  v_allowance        int;
  v_used             int;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select verified_at is not null into v_verified
    from public.profiles where id = v_uid;

  select not exists (
    select 1 from public.conversations
    where participant_b = v_uid and status = 'pending'
  ) into v_no_pending;

  select not exists (
    select 1 from public.profile_template_answers pta
    join public.question_templates qt on qt.id = pta.template_id
    where pta.profile_id = v_uid and not qt.is_active
  ) into v_no_dead_question;

  select case
           when count(*) filter (where qa.status in ('completed', 'failed_checkpoint')) = 0 then null
           else 100.0 * count(*) filter (where qa.unlocked_tier > 0)
                / count(*) filter (where qa.status in ('completed', 'failed_checkpoint'))
         end
    into v_solve_rate
    from public.quiz_attempts qa
    where qa.target_profile_id = v_uid;

  v_quiz_health := v_no_dead_question
                   and v_solve_rate is not null
                   and v_solve_rate between 10 and 85;

  select count(*) into v_photo_count from public.photos where profile_id = v_uid;
  select count(*) into v_custom_count
    from public.custom_questions where profile_id = v_uid and is_active;
  select secret_card_type is not null into v_secret_card_ok
    from public.profiles where id = v_uid;

  v_profile_complete := (v_photo_count = 7) and (v_custom_count >= 5) and v_secret_card_ok;

  v_earned := v_verified::int + v_no_pending::int + v_quiz_health::int + v_profile_complete::int;
  v_allowance := least(v_base + v_earned, v_cap);

  -- Bugün fiilen kullanılan kredi. daily_quotas satırı henüz yoksa 0.
  -- DİKKAT: hak gün içindeki İLK start_quiz çağrısında hesaplanıp
  -- daily_quotas.quiz_allowance'a SABİTLENİYOR (bkz. 20260818112446).
  -- Yani bugün bir koşul kazanılsa bile bugünkü hak değişmez, yarın değişir.
  -- İstemci bunu kullanıcıya açıkça yazmalı.
  select quiz_credits_used, quiz_allowance into v_used, v_allowance
    from public.daily_quotas
    where user_id = v_uid and date = current_date;

  if v_allowance is null then
    v_allowance := least(v_base + v_earned, v_cap);
  end if;

  return jsonb_build_object(
    'allowance', v_allowance,
    'used', coalesce(v_used, 0),
    'remaining', greatest(0, v_allowance - coalesce(v_used, 0)),
    'base', v_base,
    'cap', v_cap,
    'locked_for_today', (select exists (
      select 1 from public.daily_quotas
      where user_id = v_uid and date = current_date and quiz_allowance is not null
    )),
    'conditions', jsonb_build_array(
      jsonb_build_object('key', 'verified',           'earned', coalesce(v_verified, false),   'bonus', 1),
      jsonb_build_object('key', 'no_pending_request', 'earned', coalesce(v_no_pending, false), 'bonus', 1),
      jsonb_build_object('key', 'quiz_health',        'earned', coalesce(v_quiz_health, false),'bonus', 1,
                         'solve_rate', case when v_solve_rate is null then null
                                            else round(v_solve_rate, 0) end),
      jsonb_build_object('key', 'profile_complete',   'earned', v_profile_complete, 'bonus', 1,
                         'photo_count', v_photo_count,
                         'custom_question_count', v_custom_count,
                         'has_secret_card', coalesce(v_secret_card_ok, false))
    )
  );
end;
$$;

revoke execute on function public.get_quiz_allowance_breakdown() from public;
grant execute on function public.get_quiz_allowance_breakdown() to authenticated;

comment on function public.get_quiz_allowance_breakdown() is
  'Günlük quiz hakkının koşul koşul dökümü. get_quiz_allowance ile aynı hesabın tek kaynağı; kullanıcıya "6. hakkı nasıl kazanırım" sorusunu cevaplatmak için.';

-- =========================================================================
-- 2) get_quiz_allowance — artık breakdown'ın toplamını döndürüyor.
-- İmza, yetki kontrolü ve dönüş tipi (int) aynı; start_quiz / start_retry
-- değişmeden çalışmaya devam eder.
--
-- Not: breakdown, daily_quotas'a sabitlenmiş hak varsa onu döndürür. Bu,
-- start_quiz'in `coalesce(dq.quiz_allowance, excluded.quiz_allowance)`
-- davranışıyla tutarlı — sabitlenen değer gün boyunca değişmez.
-- =========================================================================
create or replace function public.get_quiz_allowance(p_user_id uuid)
returns int
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
  -- `p_user_id is null` ayrıca kontrol ediliyor: NULL <> v_uid ifadesi TRUE
  -- değil NULL üretir, yani yalnızca `<>` yazıldığında null argüman kontrolü
  -- sessizce atlayıp çağıranın kendi hakkını döndürürdü. Veri sızdırmıyordu
  -- ama hatalı çağrıyı görünmez kılıyordu.
  if p_user_id is null or p_user_id <> v_uid then
    raise exception 'Yalnızca kendi hakkını sorgulayabilirsin';
  end if;

  return (public.get_quiz_allowance_breakdown() ->> 'allowance')::int;
end;
$$;

revoke execute on function public.get_quiz_allowance(uuid) from public;
grant execute on function public.get_quiz_allowance(uuid) to authenticated;
