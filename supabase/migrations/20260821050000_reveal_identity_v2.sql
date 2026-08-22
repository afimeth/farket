-- reveal_identity v2: reads from the new flexible profile_identity_attributes
-- table instead of identity_card's hardcoded 5-field if-chain. name/age rows
-- are upserted here with the profile's live values on every call, so they
-- never drift out of sync with profile edits without needing a separate sync
-- job — this is the same "read at reveal time" trick the old function used
-- implicitly by joining profiles directly instead of storing name/age.

create or replace function public.reveal_identity(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_attempt   record;
  v_target    record;
  v_result    jsonb;
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

  select p.id, p.display_name, p.birth_date
    into v_target
    from public.profiles p
    where p.id = v_attempt.target_profile_id;

  if not found then
    raise exception 'Profil bulunamadı';
  end if;

  -- name/age are derived pseudo-attributes: keep their value_text/value_numeric
  -- fresh from profiles on every reveal, but preserve whatever is_shown_on_reveal
  -- the owner already set (default false on first insert, same as before).
  insert into public.profile_identity_attributes (profile_id, attribute_type, value_text, is_shown_on_reveal)
    values (v_target.id, 'name', v_target.display_name, false)
    on conflict (profile_id, attribute_type)
    do update set value_text = excluded.value_text;

  insert into public.profile_identity_attributes (profile_id, attribute_type, value_numeric, is_shown_on_reveal)
    values (v_target.id, 'age', extract(year from age(v_target.birth_date))::int, false)
    on conflict (profile_id, attribute_type)
    do update set value_numeric = excluded.value_numeric;

  select coalesce(
           jsonb_object_agg(attribute_type, coalesce(value_text, value_numeric::text)),
           '{}'::jsonb
         )
    into v_result
    from public.profile_identity_attributes
    where profile_id = v_target.id and is_shown_on_reveal;

  -- Denetim izi: aynı (viewer, target) çifti için tekrar tekrar çağrılsa
  -- bile (uygulama yeniden açıldığında künyeyi tekrar okumak gibi) bir
  -- kez kaydedilir. İlk kayıtta hedef profil sahibine bildirim gider
  -- (bkz. 20260817030545_notifications.sql — bu davranış v2'de de korunuyor).
  if not exists (
    select 1 from public.identity_reveals
    where viewer_id = v_attempt.viewer_id and target_profile_id = v_attempt.target_profile_id
  ) then
    insert into public.identity_reveals (viewer_id, target_profile_id)
      values (v_attempt.viewer_id, v_attempt.target_profile_id);

    -- identity_revealed: kimliksiz, günlük gruplanır.
    perform public._notify(
      v_attempt.target_profile_id, 'identity_revealed', null, p_attempt_id, null, '{}'::jsonb
    );
  end if;

  return v_result;
end;
$$;
