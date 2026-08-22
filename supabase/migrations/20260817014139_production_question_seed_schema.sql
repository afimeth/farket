-- Görev 1: production seed'i idempotent (tekrar çalıştırılabilir) şekilde
-- yükleyebilmek için doğal anahtar sütunları.
--
-- NOT NULL yapılmadı: mevcut pgTAP test fikstürleri question_templates/
-- taxonomies'e code olmadan satır ekliyor (int PK zaten benzersiz kimlik
-- sağlıyor onlar için). Üretim seed'i her satıra code verecek; code'un
-- kendisi kısmi UNIQUE index ile korunuyor.

alter table public.question_templates add column code text;
create unique index idx_question_templates_code on public.question_templates (code) where code is not null;

alter table public.taxonomies add column code text;
create unique index idx_taxonomies_code on public.taxonomies (code) where code is not null;

-- taxonomy_items'ın kendi doğal anahtarı yok ama (taxonomy_id, label)
-- ikilisi bir taksonomi içinde zaten mantıksal olarak benzersiz olmalı —
-- idempotent upsert için gereken ON CONFLICT hedefi bu.
alter table public.taxonomy_items add constraint taxonomy_items_taxonomy_id_label_key unique (taxonomy_id, label);
