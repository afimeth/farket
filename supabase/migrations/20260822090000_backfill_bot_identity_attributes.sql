-- Farket — bot profillerine eksik künye bilgisi (22 Ağustos).
--
-- SORUN: start_quiz'in 2. perdesi künyedeki sayısal alanlardan otomatik soru üretiyor
-- (bkz. 20260821060000_start_quiz_two_phase). Hiç `is_quiz_eligible` alanı olmayan bir
-- profilde fonksiyon 'Hedef profilin quiz için işaretlenmiş künye bilgisi yok' diye
-- patlıyor — yani o profilin quizi HİÇ başlatılamıyor.
--
-- Bot tohumlama betiği (supabase/scripts/seed_bot_profiles.py) profile_identity_attributes
-- tablosundan (20260821020000) daha eskiydi ve hiç künye yazmıyordu. Sonuç: hem yerelde
-- hem Cloud'da tohumlanmış botların tamamının quizi başlatılamaz durumdaydı, yani
-- uygulamanın çekirdek akışı test edilemiyordu. Betik düzeltildi; bu migration da
-- ZATEN OLUŞTURULMUŞ botları tamamlıyor.
--
-- KAPSAM: yalnızca `is_bot` profiller. Gerçek kullanıcılara dokunulmuyor — onlarda
-- eksikse bu bir ürün kararıdır ve kurulum sihirbazı zaten zorunlu tutuyor
-- (20260821080000_publish_profile_identity_gate).
--
-- Değerler profil id'sinden türetiliyor: her bot farklı ama tekrar çalıştırıldığında
-- aynı sonucu veriyor. `is_quiz_eligible` yalnızca height_cm/weight_kg/age için
-- serbest (tablo CHECK'i), bu yüzden boy ve kilo seçildi.

insert into public.profile_identity_attributes
  (profile_id, attribute_type, value_numeric, is_shown_on_reveal, is_quiz_eligible)
select p.id, 'height_cm', 158 + (abs(hashtext(p.id::text)) % 35), true, true
  from public.profiles p
 where coalesce(p.is_bot, false)
   and not exists (
     select 1 from public.profile_identity_attributes a
      where a.profile_id = p.id and a.attribute_type = 'height_cm'
   )
on conflict (profile_id, attribute_type) do nothing;

insert into public.profile_identity_attributes
  (profile_id, attribute_type, value_numeric, is_shown_on_reveal, is_quiz_eligible)
select p.id, 'weight_kg', 50 + (abs(hashtext(p.id::text || 'w')) % 43), true, true
  from public.profiles p
 where coalesce(p.is_bot, false)
   and not exists (
     select 1 from public.profile_identity_attributes a
      where a.profile_id = p.id and a.attribute_type = 'weight_kg'
   )
on conflict (profile_id, attribute_type) do nothing;

-- Künyedeki mesleği de aktar: identity_card.occupation zaten dolu ama reveal_identity
-- artık profile_identity_attributes'tan okuyor (20260821050000_reveal_identity_v2),
-- yani bot künyesi quiz geçildiğinde boş görünüyordu.
insert into public.profile_identity_attributes
  (profile_id, attribute_type, value_text, is_shown_on_reveal, is_quiz_eligible)
select p.id, 'job', ic.occupation, true, false
  from public.profiles p
  join public.identity_card ic on ic.profile_id = p.id
 where coalesce(p.is_bot, false)
   and ic.occupation is not null
   and not exists (
     select 1 from public.profile_identity_attributes a
      where a.profile_id = p.id and a.attribute_type = 'job'
   )
on conflict (profile_id, attribute_type) do nothing;
