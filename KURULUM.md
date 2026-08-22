# Kurulum

*[English version below](#setup-english)*

## Gereksinimler

- [Git](https://git-scm.com/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Supabase yerel stack'i için)
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- [Node.js](https://nodejs.org/) (LTS)
- Android geliştirme için: [Android Studio](https://developer.android.com/studio) veya en azından Android SDK command-line tools + JDK 17

## 1. Backend (Supabase) — yerel

```bash
git clone https://github.com/afimeth/farket.git
cd farket/supabase

supabase start            # yerel Supabase stack'ini ayağa kaldırır (Docker)
supabase db reset          # migration'ları + seed.sql'i sıfırdan uygular
supabase test db           # tüm pgTAP testlerini çalıştırır (300+ test)
```

`supabase start` çıktısındaki `API_URL`, `ANON_KEY`, `SERVICE_ROLE_KEY` ve `Studio URL`'i not al — sırasıyla Android istemcisi ve/veya test script'leri için gerekecek.

Faydalı adresler (varsayılan portlar):
- Studio (DB yönetim arayüzü): `http://127.0.0.1:54323`
- Mailpit (yerel e-posta kutusu — giriş linkleri buraya düşer): `http://127.0.0.1:54324`
- REST API: `http://127.0.0.1:54321`

### Test botlarını seed etmek (opsiyonel)

Keşfet ekranını boş görmemek için 6 test profili eklemek istersen:

```bash
cd supabase/scripts
python seed_bot_profiles.py
```

(Python 3 + `pip install psycopg2-binary requests pillow` gerekir.)

Bot profillerinin fotoğraf havuzu (`supabase/content-source/`) depo boyutunu makul
tutmak için repoya dahil edilmedi. Script fotoğraf bulamazsa botları fotoğrafsız
oluşturur; kendi görsellerini `supabase/content-source/bot_photos/<kullanıcı-adı>/1.png`
biçiminde yerleştirebilirsin.

## 2. Android istemcisi

```bash
cd android
```

`local.properties` dosyası oluştur (git'e girmez):

```properties
sdk.dir=<Android SDK yolun>
supabase.url=http://10.0.2.2:54321
```

`10.0.2.2`, Android emülatöründen host makinenin `localhost`'una erişim adresidir. Gerçek cihazda test ediyorsan bunun yerine host makinenin LAN IP'sini ya da bir tünel (örn. `trycloudflare.com`) adresini kullan.

Derleme ve kurulum:

```bash
./gradlew installDebug     # emülatör/cihaza debug APK kurar
```

### Release build (Supabase Cloud'a bağlı)

Gerçek cihaza dağıtmak için `local.properties`'e ayrıca şunlar eklenmeli:

```properties
supabase.url.release=https://<proje-ref>.supabase.co
supabase.anon.key.release=<Cloud projesinin anon/publishable key'i>
farket.keystore.file=keystore/<dosya-adı>.keystore
farket.keystore.password=<keystore şifresi>
farket.keystore.alias=<alias>
farket.keystore.aliasPassword=<alias şifresi>
```

Bu değerler olmadan `./gradlew assembleRelease` bilerek hata verir (yerel/demo yapılandırmanın release APK'ya sessizce gömülmesini önlemek için).

## 3. Supabase Cloud'a geçiş (opsiyonel, gerçek cihaz dağıtımı için)

```bash
supabase login
supabase link --project-ref <proje-ref>
supabase db push            # migration'ları Cloud'a uygular
supabase functions deploy purge-deleted-photos
```

Auth ayarı: Cloud projesinde e-posta girişi **link-tabanlı** çalışır (kod değil) — `farket://login-callback` redirect URL'inin Authentication → URL Configuration altında whitelist'te olduğundan emin ol (`supabase config push` bunu `additional_redirect_urls`'ten otomatik senkronize eder).

---

<a name="setup-english"></a>
# Setup (English)

## Prerequisites

- [Git](https://git-scm.com/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (for the local Supabase stack)
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- [Node.js](https://nodejs.org/) (LTS)
- For Android development: [Android Studio](https://developer.android.com/studio) or at least the Android SDK command-line tools + JDK 17

## 1. Backend (Supabase) — local

```bash
git clone https://github.com/afimeth/farket.git
cd farket/supabase

supabase start            # spins up the local Supabase stack (Docker)
supabase db reset          # applies migrations + seed.sql from scratch
supabase test db           # runs the full pgTAP suite (300+ tests)
```

Note the `API_URL`, `ANON_KEY`, `SERVICE_ROLE_KEY`, and `Studio URL` printed by `supabase start` — you'll need them for the Android client and/or test scripts.

Useful local addresses (default ports):
- Studio (DB admin UI): `http://127.0.0.1:54323`
- Mailpit (local mailbox — sign-in links land here): `http://127.0.0.1:54324`
- REST API: `http://127.0.0.1:54321`

### Seeding test bots (optional)

To avoid an empty discovery feed, seed 6 test profiles:

```bash
cd supabase/scripts
python seed_bot_profiles.py
```

(Requires Python 3 + `pip install psycopg2-binary requests pillow`.)

The bot photo pool (`supabase/content-source/`) is not committed, to keep the repository
small. If the script finds no photos it creates the bots without them; you can drop your
own images in as `supabase/content-source/bot_photos/<username>/1.png`.

## 2. Android client

```bash
cd android
```

Create a `local.properties` file (git-ignored):

```properties
sdk.dir=<path to your Android SDK>
supabase.url=http://10.0.2.2:54321
```

`10.0.2.2` is how the Android emulator reaches the host machine's `localhost`. On a real device, use your host's LAN IP or a tunnel (e.g. `trycloudflare.com`) instead.

Build and install:

```bash
./gradlew installDebug     # installs a debug APK on emulator/device
```

### Release build (connected to Supabase Cloud)

To ship to a real device, also add to `local.properties`:

```properties
supabase.url.release=https://<project-ref>.supabase.co
supabase.anon.key.release=<Cloud project's anon/publishable key>
farket.keystore.file=keystore/<filename>.keystore
farket.keystore.password=<keystore password>
farket.keystore.alias=<alias>
farket.keystore.aliasPassword=<alias password>
```

Without these, `./gradlew assembleRelease` fails intentionally (to prevent local/demo config from silently ending up in a release APK).

## 3. Migrating to Supabase Cloud (optional, for real-device distribution)

```bash
supabase login
supabase link --project-ref <project-ref>
supabase db push            # applies migrations to Cloud
supabase functions deploy purge-deleted-photos
```

Auth note: email sign-in on the Cloud project is **link-based** (not code-based) — make sure the `farket://login-callback` redirect URL is whitelisted under Authentication → URL Configuration (`supabase config push` syncs this automatically from `additional_redirect_urls`).
