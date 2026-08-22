-- Farket: gerekli Postgres eklentileri
-- v3: PostGIS kaldırıldı — konum artık şehir bazlı, geometri/coğrafya tipi yok.
create extension if not exists pgcrypto  with schema extensions;
