-- Farket: canlı emülatör testinde bulunan gerçek regresyon.
--
-- 20260821100000_security_hardening_grants.sql, profiles.city_id'yi UPDATE
-- grant'ından tamamen çıkarmıştı (amaç: yayınlanmış bir profilin city_id'sini
-- set_city()'nin 24 saatlik kilidini atlayarak PATCH ile değiştirememesi).
-- Ama ProfileSetupRepository.createBasicProfile() bir `upsert` kullanıyor
-- (bkz. kendi yorumu: "profil satırı zaten oluşturulmuşsa düz insert
-- profiles_pkey çakışmasıyla patlar; upsert bunu güncelleme olarak ele
-- alır") — PostgREST upsert, INSERT ... ON CONFLICT DO UPDATE'e derleniyor
-- ve gönderilen TÜM sütunlar için hem INSERT hem UPDATE yetkisi istiyor.
-- city_id UPDATE grant'ında olmayınca kurulum sihirbazının 1. adımı
-- "permission denied for table profiles" ile patlıyordu (canlı emülatörde
-- yakalandı).
--
-- Doğru çözüm: city_id/district_id'yi UPDATE grant'ına geri koy (kurulum
-- sihirbazı sırasında — profil hâlâ 'draft' iken — serbestçe düzenlenebilir
-- olması zaten normal), ama trigger ile profil 'published' olduktan SONRA
-- bu iki sütunun değişimini engelle. Böylece hem upsert akışı çalışır hem
-- de asıl güvenlik açığı (yayınlanmış profilde 24 saatlik kilidi PATCH ile
-- atlama) kapalı kalır.
--
-- Ayrıca: 20260818112658_v41_profiles_id_grant.sql'in ayrıca eklediği
-- `grant update (id)` de bu migration'ın `revoke update` satırıyla
-- kaldırılmıştı (o migration'ın kendi yorumunda anlattığı, upsert'in
-- ON CONFLICT DO UPDATE SET id = EXCLUDED.id ürettiği için gereken grant).
-- Canlı emülatör testinde aynı "permission denied for table profiles"
-- hatası İKİNCİ kez bununla tekrar alındı — id de listeye geri eklendi.

revoke update on public.profiles from authenticated;
grant update (
  id, display_name, birth_date, sex, username, age_attested_at, city_id, district_id
) on public.profiles to authenticated;

-- current_user = 'authenticated' kontrolü: set_city() (city_id/district_id
-- için) SECURITY DEFINER olduğu için çalışırken current_user fonksiyon
-- sahibi olur (authenticated DEĞİL), o yüzden bu trigger'a takılmaz. Yalnızca
-- PostgREST üzerinden DOĞRUDAN authenticated rolüyle gelen PATCH/UPDATE
-- engellenir.
create or replace function public.prevent_identity_field_change_after_publish()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'published' and current_user = 'authenticated' and (
    new.birth_date is distinct from old.birth_date
    or new.sex is distinct from old.sex
    or new.city_id is distinct from old.city_id
    or new.district_id is distinct from old.district_id
  ) then
    raise exception 'Profil yayınlandıktan sonra doğum tarihi/cinsiyet/şehir client tarafından doğrudan değiştirilemez (şehir için set_city() RPC''sini kullan)';
  end if;
  return new;
end;
$$;
