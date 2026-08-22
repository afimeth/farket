-- Farket: profiles.username — herkese açık takma ad ("@handle").
--
-- display_name'den ayrı: display_name gerçek/tam isimdir ve künye
-- açılana kadar (identity_card.show_name) hiç gösterilmez. username ise
-- keşif kartında baştan itibaren herkese açıktır (kullanıcı adı örneği:
-- "@blablabla" — "@" istemci tarafında eklenir, burada saklanan çıplak
-- handle'dır).
--
-- NOT NULL yapılmadı: taslak (draft) profillerin henüz bir username
-- seçmemiş olması normal. "Yayınlanmış profilde username zorunlu" kuralı
-- burada bir CHECK kısıtı olarak DAYATILMIYOR — mevcut test fixture'ları
-- (ve henüz yazılmamış profil yayınlama akışı, adım 4) username'siz
-- doğrudan status='published' satırlar içeriyor/içerebilir. Bunun yerine
-- discover_profiles() zaten username IS NOT NULL şartını arıyor; gerçek
-- "yayınlamak için username zorunlu" doğrulaması adım 4'teki profil
-- yayınlama fonksiyonuna ait.

alter table public.profiles add column username text;

alter table public.profiles
  add constraint profiles_username_format
  check (username is null or username ~ '^[a-z0-9_]{3,20}$');

create unique index idx_profiles_username on public.profiles (username) where username is not null;

-- Ayrı bir GRANT gerekmiyor: profiles zaten authenticated'a tablo
-- genelinde select/insert/update ile açık (grants.sql), yeni sütun buna
-- otomatik dahil.
