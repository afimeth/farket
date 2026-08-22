-- Farket: submit_answer + check_checkpoint + finish_quiz
-- (brifing v3, bölüm 9 adım 6)
--
-- Tasarım notu — v2 incelemesinden taşınan bir düzeltme: check_checkpoint
-- ayrı, istemcinin isteğe bağlı çağırdığı bir uç nokta olarak bırakılırsa,
-- istemci onu hiç çağırmayarak denemeyi sonsuza kadar 'in_progress'te
-- askıda bırakabilir (ceza hiç işlemez, ama yeniden deneme de UNIQUE
-- kısıtı yüzünden açılamaz). Bunu kapatmak için asıl değerlendirme
-- (checkpoint geçildi mi / künye kilitlensin mi) submit_answer içinde,
-- 5. cevap kaydedilir kaydedilmez OTOMATİK yapılıyor. check_checkpoint()
-- salt-okunur bir durum sorgusuna dönüştü — istemci bağlantıyı kaybedip
-- geri döndüğünde sonucu tekrar okumak için kullanılır.
-- Aynı ilke finish_quiz için de geçerli: 10. cevap kaydedilince
-- otomatik çağrılır; ayrıca idempotent bir public RPC olarak da durur
-- (bağlantı koptuysa istemci sonucu tekrar okuyabilsin diye).
--
-- template_stats güncellemesi ve taban oran filtresi kasıtlı olarak
-- burada YOK — bölüm 9 adım 7'de ayrı olarak ele alınacak.
-- "Bildirim" (hedef profil sahibine haber verme) de burada YOK — henüz
-- bir bildirim tablosu/altyapısı bu şemada tanımlı değil.

-- =========================================================================
-- submit_answer
-- =========================================================================
create or replace function public.submit_answer(
  p_attempt_id  uuid,
  p_position    int,
  p_option_id   text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id           uuid := (select auth.uid());
  v_attempt             record;
  v_correct_option      text;
  v_expected_position   int;
  v_is_correct          boolean;
  v_new_score           int;
  v_checkpoint_passed   boolean;
  v_result              jsonb;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_attempt
    from public.quiz_attempts
    where id = p_attempt_id
    for update;

  if not found or v_attempt.viewer_id <> v_viewer_id then
    raise exception 'Bu deneme sana ait değil';
  end if;

  if v_attempt.status <> 'in_progress' then
    raise exception 'Bu deneme artık aktif değil';
  end if;

  select correct_option_id into v_correct_option
    from public.attempt_questions
    where attempt_id = p_attempt_id and position = p_position;

  if not found then
    raise exception 'Geçersiz soru pozisyonu: %', p_position;
  end if;

  select count(*) + 1 into v_expected_position
    from public.attempt_answers
    where attempt_id = p_attempt_id;

  -- Bu kontrol aynı zamanda tekrar cevaplamayı da örtük olarak engeller:
  -- zaten cevaplanmış bir pozisyon hiçbir zaman "beklenen sıradaki" olamaz.
  -- attempt_answers PK'si (attempt_id, question_position) ikinci bir
  -- savunma katmanı olarak duruyor.
  if p_position <> v_expected_position then
    raise exception 'Sorulara sırayla cevap vermelisin (beklenen pozisyon: %)', v_expected_position;
  end if;

  v_is_correct := (p_option_id = v_correct_option);

  insert into public.attempt_answers (attempt_id, question_position, selected_option_id, is_correct)
    values (p_attempt_id, p_position, p_option_id, v_is_correct);

  update public.quiz_attempts
    set score = score + (case when v_is_correct then 1 else 0 end)
    where id = p_attempt_id
    returning score into v_new_score;

  v_result := jsonb_build_object('score', v_new_score);

  -- Kontrol noktası: 5. soru cevaplanınca otomatik değerlendirilir.
  if p_position = 5 then
    v_checkpoint_passed := (v_new_score >= 4);

    update public.quiz_attempts
      set checkpoint_passed = v_checkpoint_passed,
          status = case when v_checkpoint_passed then status else 'failed_checkpoint' end,
          completed_at = case when v_checkpoint_passed then completed_at else now() end
      where id = p_attempt_id;

    if not v_checkpoint_passed then
      insert into public.hidden_profiles (viewer_id, target_profile_id, hidden_until)
        values (v_attempt.viewer_id, v_attempt.target_profile_id, now() + interval '3 months')
        on conflict (viewer_id, target_profile_id)
        do update set hidden_until = excluded.hidden_until;
    end if;

    v_result := v_result || jsonb_build_object('checkpoint_passed', v_checkpoint_passed);
  end if;

  -- 10. soru cevaplanınca (ve deneme hâlâ in_progress'se) otomatik bitirilir.
  if p_position = 10 and v_attempt.status = 'in_progress' then
    v_result := v_result || public.finish_quiz(p_attempt_id);
  end if;

  return v_result;
end;
$$;

revoke execute on function public.submit_answer(uuid, int, text) from public;
grant execute on function public.submit_answer(uuid, int, text) to authenticated;

-- =========================================================================
-- check_checkpoint — salt okunur durum sorgusu (bkz. yukarıdaki tasarım notu)
-- =========================================================================
create or replace function public.check_checkpoint(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_attempt   record;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_attempt
    from public.quiz_attempts
    where id = p_attempt_id;

  if not found or v_attempt.viewer_id <> v_viewer_id then
    raise exception 'Bu deneme sana ait değil';
  end if;

  return jsonb_build_object(
    'checkpoint_passed', v_attempt.checkpoint_passed,
    'status', v_attempt.status,
    'score', v_attempt.score
  );
end;
$$;

revoke execute on function public.check_checkpoint(uuid) from public;
grant execute on function public.check_checkpoint(uuid) to authenticated;

-- =========================================================================
-- finish_quiz — idempotent: zaten sonuçlanmışsa mevcut sonucu döner.
-- =========================================================================
create or replace function public.finish_quiz(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id   uuid := (select auth.uid());
  v_attempt     record;
  v_tier        int;
  v_answered    int;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_attempt
    from public.quiz_attempts
    where id = p_attempt_id
    for update;

  if not found or v_attempt.viewer_id <> v_viewer_id then
    raise exception 'Bu deneme sana ait değil';
  end if;

  if v_attempt.status in ('completed', 'failed_checkpoint') then
    return jsonb_build_object(
      'score', v_attempt.score,
      'unlocked_tier', v_attempt.unlocked_tier,
      'status', v_attempt.status
    );
  end if;

  select count(*) into v_answered
    from public.attempt_answers
    where attempt_id = p_attempt_id;

  if v_answered < 10 then
    raise exception 'Quiz henüz tamamlanmadı (% / 10 soru cevaplandı)', v_answered;
  end if;

  v_tier := case
    when v_attempt.score >= 8 then 8
    when v_attempt.score = 7 then 7
    else 0
  end;

  if v_attempt.score < 7 then
    insert into public.hidden_profiles (viewer_id, target_profile_id, hidden_until)
      values (v_attempt.viewer_id, v_attempt.target_profile_id, now() + interval '3 months')
      on conflict (viewer_id, target_profile_id)
      do update set hidden_until = excluded.hidden_until;
  end if;

  update public.quiz_attempts
    set status = 'completed',
        unlocked_tier = v_tier,
        completed_at = now()
    where id = p_attempt_id;

  return jsonb_build_object('score', v_attempt.score, 'unlocked_tier', v_tier, 'status', 'completed');
end;
$$;

revoke execute on function public.finish_quiz(uuid) from public;
grant execute on function public.finish_quiz(uuid) to authenticated;
