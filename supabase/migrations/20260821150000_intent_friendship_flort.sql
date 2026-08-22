-- Farket: künyedeki "Niyet" alanı ürün kararıyla "Ne arıyorsun?" olarak yeniden
-- adlandırıldı ve seçenekler Arkadaşlık / Flört'e indirildi (21 Ağustos).
-- Eski 'aktivite_arkadasi' değeri artık sunulmuyor; mevcut kayıtlar 'flort'a taşınıyor
-- ki yeni CHECK kısıtı eklenirken elde geçersiz satır kalmasın.
--
-- profile_identity_attributes.value_text serbest metin (kısıt yok), ama reveal_identity
-- gerçekte oradan okuduğu için oraya kopyalanmış 'intent' satırları da güncelleniyor —
-- aksi halde künyede eski etiket görünmeye devam ederdi.

alter table public.identity_card
  drop constraint if exists identity_card_intent_check;

update public.identity_card
   set intent = 'flort'
 where intent = 'aktivite_arkadasi';

update public.profile_identity_attributes
   set value_text = 'flort'
 where attribute_type = 'intent'
   and value_text = 'aktivite_arkadasi';

alter table public.identity_card
  add constraint identity_card_intent_check
  check (intent in ('arkadaslik', 'flort'));
