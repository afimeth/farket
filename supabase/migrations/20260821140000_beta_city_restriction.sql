-- Beta kısıtı (kullanıcı kararı, 21 Ağustos): şehirler henüz tam açılmadı,
-- kurulum sihirbazı/set_city şimdilik yalnızca İstanbul'u kabul etsin.
-- Diğer 80 il `is_active=false` yapılıyor — satırlar silinmiyor (mevcut
-- referanslar/gelecekteki açılış için), yalnızca seçilebilirlik kapanıyor.
-- Android city picker zaten `is_active=true` filtresiyle çalışıyor
-- (CityRepository.kt), set_city() de aynı şartı arıyor — tek nokta.
update public.cities set is_active = false where name <> 'İstanbul';
