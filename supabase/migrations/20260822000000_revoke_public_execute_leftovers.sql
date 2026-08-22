-- Farket — sertleştirme artığı temizliği (22 Ağustos).
--
-- Postgres'te `create function` varsayılan olarak PUBLIC'e EXECUTE verir.
-- Repodaki yerleşik desen her fonksiyonda önce `revoke execute ... from public`
-- sonra hedef role `grant` yapmak (bkz. 20260821100000_security_hardening_grants).
-- Aşağıdaki beş fonksiyonda revoke adımı atlanmış ve PUBLIC grant'i duruyor,
-- yani `anon` (oturumsuz) rolü de çağırabiliyor.
--
-- Fiilî veri sızıntısı YOK: beşi de ilk iş olarak auth.uid() null ise
-- 'Oturum açılmamış' hatası fırlatıyor. Bu düzeltme derinlemesine savunma —
-- yetkilendirme yalnızca fonksiyon gövdesindeki disipline bırakılmasın diye
-- (aynı ilke: 20260818114946 içindeki secret_card CHECK'i notu).

revoke execute on function public.get_my_connections()                  from public;
revoke execute on function public.get_blocked_users()                   from public;
revoke execute on function public.get_my_template_progress()            from public;
revoke execute on function public.get_my_verification_status()          from public;
revoke execute on function public.swap_photo_positions(uuid, uuid)      from public;

-- authenticated grant'leri kendi migration'larında zaten verilmişti; revoke
-- yalnızca PUBLIC'i hedeflediği için onlar etkilenmez. Yine de açıkça
-- tekrarlanıyor ki bu dosya tek başına okunduğunda son durum belli olsun.
grant execute on function public.get_my_connections()                   to authenticated;
grant execute on function public.get_blocked_users()                    to authenticated;
grant execute on function public.get_my_template_progress()             to authenticated;
grant execute on function public.get_my_verification_status()           to authenticated;
grant execute on function public.swap_photo_positions(uuid, uuid)       to authenticated;
