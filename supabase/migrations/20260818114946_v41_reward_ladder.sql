-- Farket v4.1 — sonraki fazlar, Faz 1/6: ödül merdiveni.
--
-- Skor 7/8/9/10'un her biri farklı türde bir ayrıcalık açıyor (v4.1 §4-5):
--   7  Başvuru   50 karakterlik mesaj (DEĞİŞMEDİ)
--   8  Tanıtım   150 karakter (mevcut "100" ile aynı, doc'ta 150 yazıyor
--                 ama v3'ten beri char_limit_applied CHECK'i (50,100)
--                 idi — burada DOKUNULMADI, yalnızca referenced_photo_id
--                 eklendi; karakter sayısını 150'ye çıkarmak ayrı,
--                 istenirse sonra yapılacak bir karar, v4.1'in asıl
--                 vurgusu "farklı TÜRDE ayrıcalık" idi)
--   9  Karşılık  gizli kart açılır + asked_question (<=100 karakter)
--   10 Eşitlik   mühür (has_seal) + ters yönlü künye açılması (alıcı,
--                 gönderenin künyesini quiz çözmeden görür)
--
-- "İkinci denemede tavan 8" kuralı zaten Migration 4/5'te max_tier ile
-- kuruldu — burada yalnızca unlocked_tier'ın 9/10'a çıkabilmesi ve
-- max_tier ile sınırlanması ekleniyor.

-- =========================================================================
-- 1) quiz_attempts.unlocked_tier CHECK — 9 ve 10 eklendi.
-- =========================================================================
alter table public.quiz_attempts drop constraint quiz_attempts_unlocked_tier_check;
alter table public.quiz_attempts add constraint quiz_attempts_unlocked_tier_check
  check (unlocked_tier in (0, 7, 8, 9, 10));

-- =========================================================================
-- 2) profiles.secret_card_* için tutarlılık CHECK'i (set_secret_card bunu
-- zaten sağlıyor ama DB seviyesinde de garanti edilsin — brifingin genel
-- ilkesi: güvenlik/bütünlük yalnızca fonksiyon disiplinine bırakılmaz).
-- =========================================================================
alter table public.profiles add constraint profiles_secret_card_consistency check (
  secret_card_type is null
  or (secret_card_type = 'photo' and secret_card_photo_id is not null and secret_card_text is null)
  or (secret_card_type in ('note', 'song') and secret_card_text is not null and secret_card_photo_id is null)
);

-- =========================================================================
-- 3) finish_quiz — tier hesaplaması basitleşti: skor 7+ ise skorun kendisi
-- (max_tier ile sınırlı), aksi halde 0.
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
  v_wait        interval;
  v_cost        int;
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
    when v_attempt.score >= 7 then least(v_attempt.score, v_attempt.max_tier)
    else 0
  end;

  if v_attempt.attempt_no = 1 and v_attempt.score < 7 then
    if v_attempt.score = 6 then
      v_wait := interval '0 days'; v_cost := 2;
    elsif v_attempt.score between 4 and 5 then
      v_wait := interval '3 days'; v_cost := 3;
    else
      v_wait := interval '14 days'; v_cost := 5;
    end if;

    insert into public.hidden_profiles
      (viewer_id, target_profile_id, first_attempt_score, available_at, retry_cost, retry_used, released_early)
      values (v_attempt.viewer_id, v_attempt.target_profile_id, v_attempt.score, now() + v_wait, v_cost, false, false)
      on conflict (viewer_id, target_profile_id) do update set
        first_attempt_score = excluded.first_attempt_score,
        available_at = excluded.available_at,
        retry_cost = excluded.retry_cost,
        retry_used = false,
        released_early = false;
  end if;

  update public.quiz_attempts
    set status = 'completed',
        unlocked_tier = v_tier,
        completed_at = now()
    where id = p_attempt_id;

  if v_attempt.score >= 7 then
    perform public._notify(
      v_attempt.target_profile_id,
      case when v_attempt.score = 10 then 'perfect_score' else 'quiz_passed' end,
      null, p_attempt_id, null,
      jsonb_build_object('score', v_attempt.score)
    );
  end if;

  return jsonb_build_object('score', v_attempt.score, 'unlocked_tier', v_tier, 'status', 'completed');
end;
$$;

revoke execute on function public.finish_quiz(uuid) from public;
grant execute on function public.finish_quiz(uuid) to authenticated;

-- =========================================================================
-- 4) send_message — 8'de foto referansı, 9'da soru alanı, 10'da mühür +
-- ters yönlü künye açılması. Yeni parametreler DEFAULT NULL (eklemeli,
-- eski çağrılar bozulmaz).
-- =========================================================================
-- DİKKAT: yeni parametreler eklemek `create or replace` ile eski 2 argümanlı
-- imzayı DEĞİŞTİRMEZ (Postgres'te farklı parametre sayısı = farklı overload)
-- — eski fonksiyon açıkça DROP edilmezse iki sürüm birlikte yaşar ve
-- `send_message(hedef, gövde)` çağrıları "is not unique" hatasıyla patlar.
drop function if exists public.send_message(uuid, text);

create or replace function public.send_message(
  p_target_profile_id    uuid,
  p_body                 text,
  p_referenced_photo_id  uuid default null,
  p_asked_question       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sender_id     uuid := (select auth.uid());
  v_conversation  record;
  v_tier          int;
  v_char_limit    int;
  v_conv_id       uuid;
  v_calls_used    int;
begin
  if v_sender_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  if v_sender_id = p_target_profile_id then
    raise exception 'Kendine mesaj gönderemezsin';
  end if;

  if exists (
    select 1 from public.blocks
    where (blocker_id = v_sender_id and blocked_id = p_target_profile_id)
       or (blocker_id = p_target_profile_id and blocked_id = v_sender_id)
  ) then
    raise exception 'Bu kullanıcıyla mesajlaşma engellenmiş';
  end if;

  select * into v_conversation
    from public.conversations
    where (participant_a = v_sender_id and participant_b = p_target_profile_id)
       or (participant_a = p_target_profile_id and participant_b = v_sender_id)
    for update;

  if not found then
    select unlocked_tier into v_tier
      from public.quiz_attempts
      where viewer_id = v_sender_id and target_profile_id = p_target_profile_id
        and status = 'completed' and unlocked_tier > 0;

    if not found then
      raise exception 'Bu kişiye mesaj isteği gönderme hakkın yok (en az 7 doğru cevap gerekiyor)';
    end if;

    v_char_limit := case when v_tier >= 8 then 100 else 50 end;

    if char_length(p_body) > v_char_limit then
      raise exception 'İlk mesaj en fazla % karakter olabilir', v_char_limit;
    end if;

    if p_referenced_photo_id is not null then
      if v_tier < 8 then
        raise exception 'Fotoğraf referansı göndermek için en az 8 doğru cevap gerekiyor';
      end if;
      if not exists (
        select 1 from public.photos
        where id = p_referenced_photo_id and profile_id = p_target_profile_id and moderation_status = 'approved'
      ) then
        raise exception 'Geçersiz fotoğraf referansı';
      end if;
    end if;

    if p_asked_question is not null then
      if v_tier < 9 then
        raise exception 'Soru sormak için en az 9 doğru cevap gerekiyor';
      end if;
      if char_length(p_asked_question) > 100 then
        raise exception 'Sorulan soru en fazla 100 karakter olabilir';
      end if;
    end if;

    insert into public.conversations (participant_a, participant_b, status, expires_at, unlocked_tier, has_seal)
      values (v_sender_id, p_target_profile_id, 'pending', now() + interval '7 days', v_tier, v_tier = 10)
      returning id into v_conv_id;

    insert into public.messages
      (conversation_id, sender_id, body, char_limit_applied, referenced_photo_id, asked_question)
      values (v_conv_id, v_sender_id, p_body, v_char_limit, p_referenced_photo_id, p_asked_question);

    select message_requests_used into v_calls_used
      from public.daily_quotas where user_id = v_sender_id and date = current_date;
    if coalesce(v_calls_used, 0) >= 10 then
      raise exception 'Günlük mesaj isteği kotan doldu';
    end if;

    insert into public.daily_quotas as dq (user_id, date, message_requests_used)
      values (v_sender_id, current_date, 1)
      on conflict (user_id, date)
      do update set message_requests_used = dq.message_requests_used + 1;

    perform public._notify(
      p_target_profile_id, 'message_request', v_sender_id, null, v_conv_id, '{}'::jsonb
    );

    -- 10/10 (Eşitlik): mühür zaten conversations.has_seal'e yazıldı.
    -- Ters yönlü künye açılması: alıcı, gönderenin künyesini QUIZ ÇÖZMEDEN
    -- görebilsin diye identity_reveals'a TERS yönde bir kayıt (denetim
    -- izi tutarlılığı için) + get_sender_identity() ile fiilen erişim.
    if v_tier = 10 then
      if not exists (
        select 1 from public.identity_reveals
        where viewer_id = p_target_profile_id and target_profile_id = v_sender_id
      ) then
        insert into public.identity_reveals (viewer_id, target_profile_id)
          values (p_target_profile_id, v_sender_id);
      end if;
    end if;

    return jsonb_build_object('conversation_id', v_conv_id, 'status', 'pending');
  end if;

  if v_conversation.status = 'accepted' then
    insert into public.messages (conversation_id, sender_id, body, char_limit_applied)
      values (v_conversation.id, v_sender_id, p_body, null);
    return jsonb_build_object('conversation_id', v_conversation.id, 'status', 'accepted');
  end if;

  if v_conversation.status = 'pending' and v_conversation.participant_a = v_sender_id then
    raise exception 'Zaten bekleyen bir mesaj isteğin var, karşı taraf kabul etmeden yeni mesaj gönderemezsin';
  end if;

  if v_conversation.status = 'pending' then
    raise exception 'Önce mesaj isteğini kabul etmelisin';
  end if;

  raise exception 'Bu konuşma kapalı';
end;
$$;

revoke execute on function public.send_message(uuid, text, uuid, text) from public;
grant execute on function public.send_message(uuid, text, uuid, text) to authenticated;

-- =========================================================================
-- 5) get_sender_identity — 10/10 mührü olan konuşmada ALICI, göndereni
-- QUİZ ÇÖZMEDEN görebilir. reveal_identity ile aynı alan-bazlı filtreleme
-- (identity_card.show_*), yalnızca tetikleyici farklı (attempt+checkpoint
-- yerine conversation+has_seal).
-- =========================================================================
create or replace function public.get_sender_identity(p_conversation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_conv      record;
  v_card      record;
  v_result    jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_conv from public.conversations where id = p_conversation_id;

  if not found or v_conv.participant_b <> v_uid then
    raise exception 'Bu konuşma sana ait değil';
  end if;

  if not v_conv.has_seal then
    raise exception 'Bu konuşmada mühür yok (gönderen 10/10 yapmadı)';
  end if;

  select p.display_name, p.birth_date,
         ic.show_name, ic.show_age, ic.show_occupation, ic.show_city, ic.show_intent,
         ic.occupation, ic.intent,
         c.name as city_name
    into v_card
    from public.profiles p
    join public.identity_card ic on ic.profile_id = p.id
    join public.cities c on c.id = p.city_id
    where p.id = v_conv.participant_a;

  if not found then
    raise exception 'Künye bulunamadı';
  end if;

  if v_card.show_name then
    v_result := v_result || jsonb_build_object('name', v_card.display_name);
  end if;
  if v_card.show_age then
    v_result := v_result || jsonb_build_object('age', extract(year from age(v_card.birth_date))::int);
  end if;
  if v_card.show_occupation then
    v_result := v_result || jsonb_build_object('occupation', v_card.occupation);
  end if;
  if v_card.show_city then
    v_result := v_result || jsonb_build_object('city', v_card.city_name);
  end if;
  if v_card.show_intent then
    v_result := v_result || jsonb_build_object('intent', v_card.intent);
  end if;

  return v_result;
end;
$$;

revoke execute on function public.get_sender_identity(uuid) from public;
grant execute on function public.get_sender_identity(uuid) to authenticated;

-- =========================================================================
-- 6) set_secret_card / get_secret_card — 9. basamağın gizli kartı.
-- =========================================================================
create or replace function public.set_secret_card(
  p_type      text,
  p_photo_id  uuid default null,
  p_text      text default null
)
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

  if p_type not in ('photo', 'note', 'song') then
    raise exception 'Geçersiz gizli kart türü';
  end if;

  if p_type = 'photo' then
    if p_photo_id is null then
      raise exception 'Fotoğraf türünde gizli kart için photo_id gerekli';
    end if;
    if not exists (select 1 from public.photos where id = p_photo_id and profile_id = v_uid) then
      raise exception 'Seçilen fotoğraf sana ait değil';
    end if;
    update public.profiles
      set secret_card_type = 'photo', secret_card_photo_id = p_photo_id, secret_card_text = null
      where id = v_uid;
  else
    if p_text is null or char_length(p_text) = 0 then
      raise exception 'Not/şarkı türünde gizli kart için metin gerekli';
    end if;
    if char_length(p_text) > 300 then
      raise exception 'Gizli kart metni en fazla 300 karakter olabilir';
    end if;
    update public.profiles
      set secret_card_type = p_type, secret_card_text = p_text, secret_card_photo_id = null
      where id = v_uid;
  end if;
end;
$$;

revoke execute on function public.set_secret_card(text, uuid, text) from public;
grant execute on function public.set_secret_card(text, uuid, text) to authenticated;

create or replace function public.get_secret_card(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_attempt record;
  v_card    record;
begin
  if v_uid is null then
    raise exception 'Oturum açılmamış';
  end if;

  select * into v_attempt from public.quiz_attempts where id = p_attempt_id;

  if not found or v_attempt.viewer_id <> v_uid then
    raise exception 'Bu deneme sana ait değil';
  end if;

  if v_attempt.attempt_no <> 1 or v_attempt.score < 9 then
    raise exception 'Gizli kart yalnızca ilk denemede en az 9 doğru cevapla açılır';
  end if;

  select secret_card_type, secret_card_photo_id, secret_card_text into v_card
    from public.profiles where id = v_attempt.target_profile_id;

  if v_card.secret_card_type is null then
    raise exception 'Bu profilin gizli kartı yok';
  end if;

  return jsonb_build_object(
    'type', v_card.secret_card_type,
    'photo_id', v_card.secret_card_photo_id,
    'text', v_card.secret_card_text
  );
end;
$$;

revoke execute on function public.get_secret_card(uuid) from public;
grant execute on function public.get_secret_card(uuid) to authenticated;
