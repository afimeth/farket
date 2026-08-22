"""
Bot fikstürünü SQL anlık görüntüsüne döker.

Neden var: `supabase db reset` veritabanını sıfırlar ve o ana kadarki bot
hesapları silinirdi; her seferinde seed_bot_profiles.py'yi elle çalıştırmak
gerekiyordu. Bu betik mevcut 6 botu (auth kullanıcısı, profil, künye, kalıp
cevapları, serbest sorular, fotoğraf satırları ve Storage nesne kayıtları)
tek bir idempotent SQL dosyasına yazar. Dosya supabase/config.toml içindeki
db.seed.sql_paths listesinde olduğu için her reset'ten sonra kendiliğinden
geri yüklenir.

Fiziksel görsel dosyaları Storage'ın docker volume'unda durur ve db reset
onlara dokunmaz; volume de silinirse (supabase stop --no-backup, docker
volume prune) fikstür seed_bot_profiles.py ile yeniden kurulmalıdır.

Kullanım:
  python supabase/scripts/dump_bot_fixture.py
"""
from pathlib import Path

import psycopg2

DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
OUT = Path(__file__).resolve().parents[1] / "seeds" / "002_bot_fixture.sql"

# (şema.tablo, çakışma anahtarı) — sıra FK bağımlılıklarına göre.
TABLES = [
    ("auth.users", "id"),
    ("public.profiles", "id"),
    ("public.identity_card", "profile_id"),
    ("public.profile_identity_attributes", "id"),
    ("public.profile_template_answers", "profile_id, template_id"),
    ("public.custom_questions", "id"),
    ("public.custom_options", "id"),
    ("public.photos", "id"),
    ("storage.objects", "id"),
]

# Her tablo için yalnızca bot satırlarını seçen filtre.
WHERE = {
    "auth.users": "id in (select id from public.profiles where is_bot)",
    "public.profiles": "is_bot",
    "public.identity_card": "profile_id in (select id from public.profiles where is_bot)",
    "public.profile_identity_attributes": "profile_id in (select id from public.profiles where is_bot)",
    "public.profile_template_answers": "profile_id in (select id from public.profiles where is_bot)",
    "public.custom_questions": "profile_id in (select id from public.profiles where is_bot)",
    "public.custom_options": "question_id in (select id from public.custom_questions where profile_id in (select id from public.profiles where is_bot))",
    "public.photos": "profile_id in (select id from public.profiles where is_bot)",
    "storage.objects": "bucket_id = 'profile-photos'",
}


# storage.objects şeması storage-api konteyner sürümüyle birlikte değişiyor
# (archived_at / is_delete_marker / is_versioned gibi sütunlar yeni imajlarda var,
# eskilerde yok). Fikstür her CLI/imaj sürümünde uygulanabilsin diye bu tabloda
# yalnızca çekirdek sütunlar dump edilir; kalanlar servis varsayılanına düşer.
COLUMN_OVERRIDES = {
    "storage.objects": ["id", "bucket_id", "name", "owner", "owner_id", "metadata"],
}


def columns(cur, schema: str, table: str) -> list[str]:
    override = COLUMN_OVERRIDES.get(f"{schema}.{table}")
    if override:
        return override
    cur.execute(
        "select column_name from information_schema.columns "
        "where table_schema = %s and table_name = %s "
        "and is_generated = 'NEVER' order by ordinal_position",
        (schema, table),
    )
    return [r[0] for r in cur.fetchall()]


def main() -> None:
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    parts: list[str] = [
        "-- OTOMATİK ÜRETİLDİ — elle düzenleme; supabase/scripts/dump_bot_fixture.py çalıştır.",
        "-- 6 bot hesabının kalıcı fikstürü. db reset sonrası kendiliğinden geri yüklenir",
        "-- (config.toml → db.seed.sql_paths). Beta testleri bu hesaplar üzerinden yürür.",
        "",
    ]

    for qualified, conflict in TABLES:
        schema, table = qualified.split(".")
        cols = columns(cur, schema, table)
        collist = ", ".join(f'"{c}"' for c in cols)
        # Botlar parolayla giriş yapmaz; hash public repoya girmesin diye
        # yerine sabit bir yer tutucu yazılır (tests.create_supabase_user ile aynı).
        def value_expr(c: str) -> str:
            if qualified == "public.custom_questions" and c == "correct_option_id":
                return "'null'"
            if qualified == "auth.users" and c == "encrypted_password":
                return "'''x'''"
            return f'quote_nullable("{c}")'

        values_expr = ", ".join(value_expr(c) for c in cols)
        cur.execute(
            f"select 'insert into {qualified} ({collist}) values (' || "
            f"concat_ws(', ', {values_expr}) || "
            f"') on conflict ({conflict}) do nothing;' "
            f"from {qualified} where {WHERE[qualified]}"
        )
        rows = [r[0] for r in cur.fetchall()]
        parts.append(f"-- {qualified}: {len(rows)} satır")
        parts.extend(rows)
        parts.append("")

    # Bir trigger, correct_option_id'nin aynı soruya ait bir custom_options
    # satırı olmasını şart koşuyor. Seçenekler sorulardan sonra eklendiği için
    # soru satırları null ile girer, doğru şık en sonda işaretlenir.
    cur.execute(
        "select 'update public.custom_questions set correct_option_id = ' || "
        "quote_literal(correct_option_id::text) || ' where id = ' || "
        "quote_literal(id::text) || ';' from public.custom_questions "
        "where correct_option_id is not null and profile_id in "
        "(select id from public.profiles where is_bot)"
    )
    updates = [r[0] for r in cur.fetchall()]
    parts.append(f"-- doğru şık işaretlemesi: {len(updates)} soru")
    parts.extend(updates)
    parts.append("")

    OUT.write_text("\n".join(parts), encoding="utf-8")
    print(f"{OUT} yazıldı ({sum(1 for p in parts if p.startswith('insert'))} insert).")
    conn.close()


if __name__ == "__main__":
    main()
