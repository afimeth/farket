-- Görev 5 sonrası bilinen boşluk kapatması: purge_deleted_accounts() hiçbir
-- şey tarafından otomatik tetiklenmiyordu. pg_cron ile günde bir kez
-- (03:00 UTC) çağrılacak şekilde zamanlandı.
--
-- Kapsam sınırı — bu HÂLÂ tam çözüm değil: purge_deleted_accounts() artık
-- silinen fotoğrafların storage yollarını (deleted_photo_paths) döndürüyor
-- ama pg_cron bu dönüş değerini hiçbir yere iletmiyor (SELECT sonucu
-- job_run_details'e loglanır, başka bir işlem tetiklemez). Yani DB
-- satırları artık otomatik temizleniyor; Storage'daki gerçek dosyaların
-- silinmesi hâlâ ayrı bir dış süreç (service-role ile Storage API'yi
-- çağıran bir Edge Function/harici script, job_run_details'ten paths'i
-- okuyup silme) gerektiriyor — bu, saf SQL'in yapamadığı kısım (bkz.
-- 20260817040000_photo_storage.sql'deki not: storage.objects'e doğrudan
-- DELETE, protect_objects_delete trigger'ı tarafından engelleniyor).
create extension if not exists pg_cron;

select cron.schedule(
  'purge-deleted-accounts-daily',
  '0 3 * * *',
  $$select public.purge_deleted_accounts();$$
);
