-- Farket: reveal_identity
--
-- v3'ün bölüm 7 fonksiyon listesinde var ama bölüm 9'un hiçbir adımına
-- açıkça atanmamış. Mesajlaşmanın (adım 10) mantıksal ön koşulu olduğu
-- için (checkpoint geçilince künye açılır, mesaj hakkı skor 7+'da doğar)
-- burada, adım 10'a girmeden önce tamamlanıyor.
--
-- Alan bazlı filtreleme identity_card.show_* bayraklarına göre yapılır —
-- RLS ile değil, burada (brifing bölüm 2.2 / 8 madde 3). "Bildirim"
-- (hedef profil sahibine haber verme) burada YOK — şemada henüz bir
-- notifications tablosu/altyapısı tanımlı değil (submit_answer/finish_quiz
-- ile aynı bilinen boşluk).

create or replace function public.reveal_identity(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_attempt   record;
  v_card      record;
  v_result    jsonb := '{}'::jsonb;
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

  if not v_attempt.checkpoint_passed then
    raise exception 'Checkpoint geçilmeden künye açılamaz';
  end if;

  select p.display_name, p.birth_date,
         ic.show_name, ic.show_age, ic.show_occupation, ic.show_city, ic.show_intent,
         ic.occupation, ic.intent,
         c.name as city_name
    into v_card
    from public.profiles p
    join public.identity_card ic on ic.profile_id = p.id
    join public.cities c on c.id = p.city_id
    where p.id = v_attempt.target_profile_id;

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

  -- Denetim izi: aynı (viewer, target) çifti için tekrar tekrar çağrılsa
  -- bile (uygulama yeniden açıldığında künyeyi tekrar okumak gibi) bir
  -- kez kaydedilir.
  if not exists (
    select 1 from public.identity_reveals
    where viewer_id = v_attempt.viewer_id and target_profile_id = v_attempt.target_profile_id
  ) then
    insert into public.identity_reveals (viewer_id, target_profile_id)
      values (v_attempt.viewer_id, v_attempt.target_profile_id);
  end if;

  return v_result;
end;
$$;

revoke execute on function public.reveal_identity(uuid) from public;
grant execute on function public.reveal_identity(uuid) to authenticated;
