# farket

**Görmeden önce fark et.**

Farket, birinin profilini görebilmek için önce o kişiyi tanımanı isteyen bir tanışma ve keşif uygulamasıdır. Karşındaki kişinin fotoğrafları ve kendi yazdığı sorulardan oluşan bir quiz çözersin; yeterince doğru cevap verirsen künyesi (isim, yaş, meslek gibi bilgiler) açılır ve o kişiyle mesajlaşma hakkı kazanırsın. Yanılırsan o profil sana birkaç günlüğüne kapanır.

> **Beta.** Aktif geliştirme aşamasında; şema ve API değişebilir.

> **Bu depo: `farket` — herkese açık beta sürümü.**
> Yayınlanan APK'da sabit kodlu test girişi kapalıdır; giriş yalnızca e-posta
> bağlantısıyla yapılır. İç geliştirme deposu ayrıdır: **`farket-internal`** (özel).
> Otomatik araçlarla yükleme yaparken bu ikisini karıştırma — herkese açık olan
> budur.

---

## Neden böyle bir uygulama?

Tanışma uygulamalarının çoğu aynı döngüye sıkışmış durumda: sonsuz bir yüz akışı, saniyede alınan kararlar, karşılıklı eşleşen ama hiç konuşmayan insanlar. Sorun ilgi eksikliği değil — sürtünme eksikliği. Hiçbir şeye mal olmayan bir eşleşmenin kimsenin gözünde bir değeri olmuyor.

Farket bu döngüyü tersine çevirmek için üç karar üzerine kuruldu:

**1. Dikkat ücretsiz olmamalı.** Bir profili açmak emek ister. Quiz, karşındaki kişinin kendi yazdığı sorulardan oluşur; onu gerçekten okumadan geçemezsin. Bu yüzden Farket'te "kaydırıp geçmek" diye bir şey yok.

**2. Kaybetmenin bedeli olmalı.** Yanlış cevaplar profili kapatır, günlük quiz hakkı sınırlıdır. Kazanılan künye, hak edilmiş bir sayıyla başlar — ve iki taraf da bunu bilir.

**3. Konuşma, ödülün kendisidir.** Mesajlaşma bir varsayılan değil, quizle kazanılan bir haktır. Bu yüzden Farket'te açılan her sohbetin bir başlangıç hikâyesi olur.

Hedefimiz, insanların birbiriyle nitelikli iletişim kurduğu; aracı kurum olan uygulamanın ise mümkün olan en kolay, en zahmetsiz ve en keyifli deneyimi sunduğu bir yer kurmak. Kullanıcı her an nerede olduğunu, ne yaptığını ve kendisine ne olduğunu bilmeli; uygulama araya girmemeli.

## Nasıl çalışır

1. **Keşfet** — Her profil tam ekran bir karttır. Kartta yalnızca fotoğraflar ve kullanıcı adı vardır; künye kapalı doğar. Yukarı kaydırırsan quize girersin, aşağı kaydırırsan atlarsın.
2. **Quiz** — Girmeden önce şehir, fotoğraf sayısı ve zorluk gösterilir; hak harcanmadan iki kez onay alınır. Sorular o kişinin fotoğraflarına ve kendi yazdığı cevaplara dayanır. Geri dönüş, atlama ve ipucu yoktur.
3. **Künye** — Yeterince doğru cevap verirsen kimlik bilgileri açılır. Skor yükseldikçe bir ödül merdiveni ilerler: belirli bir fotoğrafa referans verme, soru sorma hakkı, "gizli kart" gibi ek ödüller açılır.
4. **Mesajlaşma** — Künye açıldıktan sonra o kişiyle konuşma hakkı kazanılır.

**Hak ekonomisi.** Herkes günde üç quiz hakkıyla başlar. Doğrulanmış hesap, bekleyen mesaj isteğinin olmaması, dengeli bir quiz ve tam profil birer hak daha ekler — tavan yedi. Günün hakkı günün ilk quizinde sabitlenir. Başarısız bir tur profili üç gün kapatır; "beklemedeki profiller" bölümünden haftada bir kez erken açılabilir.

## Teknoloji

- **Backend:** [Supabase](https://supabase.com) — Postgres 17, Auth, Storage, Edge Functions. İş kuralları RLS politikaları ve PL/pgSQL RPC'lerinde; 300+ pgTAP testiyle korunuyor.
- **İstemci:** Android — Kotlin, Jetpack Compose, Supabase Kotlin client.
- **Giriş:** E-posta bağlantısıyla deep-link doğrulama; şifre yok. Geliştirme derlemesindeki sabit kodlu kısayol bu dağıtımda derleme bayrağıyla kapatılmıştır.
- **Tipografi:** Fraunces (başlıklar), Archivo (gövde), IBM Plex Mono (etiketler).
- **Tema:** Üç renk yönü — Oda (bordo/amber), Fener (nötr gri/sarı), Alaca (mor/mercan) — her biri gece ve gündüz varyantlı.

## Depo yapısı

```
android/     Android istemcisi (Kotlin + Jetpack Compose)
supabase/    Migration'lar, RPC'ler, Edge Functions, pgTAP testleri
KURULUM.md   Yerel geliştirme ortamı kurulumu (TR + EN)
```

## Kurulum

Yerel geliştirme ortamını ayağa kaldırmak için: [`KURULUM.md`](KURULUM.md)

Derlenmiş beta APK'sı için deponun [Releases](https://github.com/afimeth/farket/releases) bölümüne bak.

## Beta kısıtları

- Şehir seçimi beta boyunca yalnızca **İstanbul**'a açıktır.
- Sabit kodlu test girişi bu dağıtımda **kapalıdır** (hem istemcide hem sunucuda); giriş yalnızca e-posta bağlantısıyla yapılır.
- Silinen fotoğrafların fiziksel temizliği henüz zamanlanmış bir iş olarak kurulmadı.

## Lisans

Henüz belirlenmedi.

---

<br>

# farket (English)

**Notice before you see.**

Farket is a dating and discovery app that asks you to know someone before you can see them. You solve a quiz built from that person's photos and self-written questions; answer enough correctly and their identity card (name, age, occupation) unlocks, along with the right to message them. Get it wrong and the profile closes to you for a few days.

> **Beta.** Actively under development; schema and API may change.

> **This repository: `farket` — the public beta.**
> The published APK ships with the fixed-code test login disabled; sign-in is by
> email link only. Internal development lives in a separate, private repository:
> **`farket-internal`**. When uploading with automated tooling, don't mix the two —
> this is the public one.

## Why build this?

Most dating apps are stuck in the same loop: an endless stream of faces, decisions made in a second, mutual matches that never turn into conversations. The problem isn't a lack of interest — it's a lack of friction. A match that costs nothing is worth nothing.

Farket is built on three decisions meant to invert that loop:

**1. Attention shouldn't be free.** Opening a profile takes effort. The quiz is written by the person you're looking at; you can't pass it without actually reading them. That's why there is no swiping-to-dismiss in Farket.

**2. Losing should cost something.** Wrong answers close the profile, and daily quiz credits are limited. An unlocked identity starts with a number that was earned — and both sides know it.

**3. The conversation is the reward.** Messaging isn't a default, it's a right won through the quiz. Every chat that opens in Farket has an origin story.

Our goal is a place where people communicate with substance, and where the app in the middle offers the easiest, least effortful, most enjoyable experience possible. Users should always know where they are, what they're doing, and what has happened to them; the app should stay out of the way.

## How it works

1. **Discover** — Each profile is a full-screen card showing only photos and a username; the identity card starts closed. Swipe up to take the quiz, down to skip.
2. **Quiz** — Before you enter, you see the city, photo count and difficulty; you confirm twice before a credit is spent. Questions draw on that person's photos and their own answers. No going back, no skipping, no hints.
3. **Identity** — Answer enough correctly and their details unlock. As your score climbs, a reward ladder unlocks extras: referencing a specific photo, asking a question, a "secret card."
4. **Messaging** — Once the identity card is open, you've earned the right to talk.

**Credit economy.** Everyone starts with three quiz credits per day. A verified account, no pending message requests, a balanced quiz and a complete profile each add one — capped at seven. The day's allowance is fixed at your first quiz. A failed round closes a profile for three days; it can be released early once a week from "pending profiles."

## Tech stack

- **Backend:** [Supabase](https://supabase.com) — Postgres 17, Auth, Storage, Edge Functions. Business rules live in RLS policies and PL/pgSQL RPCs, guarded by 300+ pgTAP tests.
- **Client:** Android — Kotlin, Jetpack Compose, Supabase Kotlin client.
- **Auth:** Deep-link email verification; no passwords. The development build's fixed-code shortcut is compiled out of this distribution.
- **Typography:** Fraunces (display), Archivo (body), IBM Plex Mono (labels).
- **Theme:** Three color directions — Oda, Fener, Alaca — each with night and day variants.

## Repository layout

```
android/     Android client (Kotlin + Jetpack Compose)
supabase/    Migrations, RPCs, Edge Functions, pgTAP tests
KURULUM.md   Local development setup (Turkish + English)
```

## Setup

To get a local development environment running, see [`KURULUM.md`](KURULUM.md).

For a compiled beta APK, see the repository's [Releases](https://github.com/afimeth/farket/releases).

## Beta limitations

- City selection is limited to **İstanbul** during beta.
- The fixed-code test login is **disabled** in this distribution (both client and server); sign-in is by email link only.
- Physical cleanup of deleted photos is not yet scheduled as a recurring job.

## License

Not yet decided.
