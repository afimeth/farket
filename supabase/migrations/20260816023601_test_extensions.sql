-- pgTAP: bölüm 6'daki güvenlik testlerini çalıştırmak için.
-- Test kütüphanesidir, çağrılmadığı sürece çalışma zamanında etkisizdir.
create extension if not exists pgtap with schema extensions;
