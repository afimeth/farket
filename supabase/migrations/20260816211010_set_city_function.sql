-- Farket: set_city (brifing v3, bölüm 9 adım 2 — kalan kısım)
--
-- Kurallar (bölüm 1, "Şehir değişimi kuralı"):
--   * Yalnızca kapalı/aktif şehir listesinden seçilebilir.
--   * Son değişimden 24 saat geçmeden yeni değişim kabul edilmez.
--   * Aynı şehir tekrar seçilirse (gerçek bir değişim değilse) kural
--     uygulanmaz, sessizce no-op döner — kullanıcı 24 saatlik kilide
--     "kendi şehrini onaylayarak" takılmamalı.
--   * district_id v1'de kullanılmıyor ama şehir değişince eski şehre ait
--     kalıp bir ilçe referansı bırakmamak için sıfırlanıyor.

create or replace function public.set_city(p_city_id int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_viewer_id uuid := (select auth.uid());
  v_profile   record;
begin
  if v_viewer_id is null then
    raise exception 'Oturum açılmamış';
  end if;

  if not exists (select 1 from public.cities where id = p_city_id and is_active) then
    raise exception 'Geçersiz şehir';
  end if;

  select city_id, city_changed_at into v_profile
    from public.profiles
    where id = v_viewer_id
    for update;

  if not found then
    raise exception 'Profil bulunamadı';
  end if;

  if v_profile.city_id = p_city_id then
    return jsonb_build_object('city_id', p_city_id, 'changed', false);
  end if;

  if v_profile.city_changed_at is not null
     and v_profile.city_changed_at > now() - interval '24 hours'
  then
    raise exception 'Şehir değişikliği için 24 saat beklemelisin (son değişim: %)', v_profile.city_changed_at;
  end if;

  update public.profiles
    set city_id = p_city_id,
        district_id = null,
        city_changed_at = now()
    where id = v_viewer_id;

  return jsonb_build_object('city_id', p_city_id, 'changed', true);
end;
$$;

revoke execute on function public.set_city(int) from public;
grant execute on function public.set_city(int) to authenticated;
