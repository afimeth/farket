-- =========================================================================
-- get_my_template_progress()
-- Bulgu (frontend, kritik): kurulum sihirbazının adım/ilerleme durumu yalnızca
-- ProfileSetupViewModel'in belleğinde tutuluyordu — süreç öldürülüp uygulama
-- yeniden açıldığında sunucuda zaten kayıtlı ilerlemeye rağmen sihirbaz 1. adıma
-- resetleniyordu. profiles/identity_card/photos/custom_questions zaten
-- `authenticated`e SELECT ile açık (bkz. grants.sql), sihirbaz bunlardan kendi
-- ilerlemesini okuyabilir. Tek okunamayan parça profile_template_answers'tı
-- (kasıtlı olarak hiç GRANT yok, bkz. grants.sql satır 9-11) — bu fonksiyon
-- yalnızca "kendi cevapladığım kalıp soru id'leri + zorlukları"nı döner
-- (doğru cevap/taksonomi içeriği yok, sızıntı riski yok), tıpkı
-- set_template_answer/remove_template_answer gibi SECURITY DEFINER üzerinden.
-- =========================================================================
create or replace function public.get_my_template_progress()
returns table (template_id int, difficulty text)
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

  return query
    select pta.template_id, pta.difficulty
    from public.profile_template_answers pta
    where pta.profile_id = v_uid;
end;
$$;

grant execute on function public.get_my_template_progress() to authenticated;
