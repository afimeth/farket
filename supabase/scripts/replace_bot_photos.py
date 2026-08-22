"""
Zaten var olan (daha önce seed_bot_profiles.py ile 'published' yapılmış) bot
profillerinin PIL placeholder fotoğraflarını, download_ai_faces.py ile
indirilmiş gerçek fotoğraflarla değiştirir. seed_bot_profiles.py'yi tekrar
çalıştırmak username/email çakışmasından patlar; bu script sadece storage'a
yeni dosya yükleyip photos tablosundaki path'leri günceller.

Kullanım:
  python supabase/scripts/replace_bot_photos.py

Önkoşul: `supabase start` çalışıyor olmalı, botlar zaten 'published' olmalı,
supabase/content-source/ai_faces/<username>/1-5.jpg dosyaları hazır olmalı.
"""
import uuid
from pathlib import Path

import psycopg2
import requests

API_URL = "http://127.0.0.1:54321"
DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
SERVICE_ROLE_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0."
    "EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
)
PROJECT_ROOT = Path(__file__).resolve().parents[2]
AI_FACES_DIR = PROJECT_ROOT / "supabase" / "content-source" / "ai_faces"

USERNAMES = [
    "elifyzmn", "kaanaydemir", "zeynepklc",
    "emrekorkmaz", "selinarslan", "burakdemirtas",
]


def admin_headers():
    return {"apikey": SERVICE_ROLE_KEY, "Authorization": f"Bearer {SERVICE_ROLE_KEY}"}


def upload_photo(profile_id: str, image_bytes: bytes, suffix: str) -> str:
    object_name = f"{profile_id}/{uuid.uuid4()}_{suffix}.jpg"
    resp = requests.post(
        f"{API_URL}/storage/v1/object/profile-photos/{object_name}",
        headers={**admin_headers(), "Content-Type": "image/jpeg"},
        data=image_bytes,
        timeout=10,
    )
    resp.raise_for_status()
    return object_name


def delete_old_object(object_name: str) -> None:
    requests.delete(
        f"{API_URL}/storage/v1/object/profile-photos/{object_name}",
        headers=admin_headers(),
        timeout=10,
    )


def main() -> None:
    conn = psycopg2.connect(DB_URL)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            for username in USERNAMES:
                folder = AI_FACES_DIR / username
                photo_files = sorted(folder.glob("*.jpg"), key=lambda p: int(p.stem))
                if not photo_files:
                    print(f"@{username}: ai_faces klasöründe dosya yok, atlanıyor")
                    continue

                cur.execute("select id from public.profiles where username = %s", (username,))
                row = cur.fetchone()
                if row is None:
                    print(f"@{username}: profil bulunamadı, atlanıyor")
                    continue
                profile_id = str(row[0])

                cur.execute(
                    "select id, position, storage_path_full, storage_path_thumb "
                    "from public.photos where profile_id = %s order by position",
                    (profile_id,),
                )
                existing = cur.fetchall()
                print(f"@{username}: {len(existing)} mevcut foto, {len(photo_files)} yeni foto")

                for (photo_id, position, old_full, old_thumb), file_path in zip(existing, photo_files):
                    img_bytes = file_path.read_bytes()
                    new_full = upload_photo(profile_id, img_bytes, "full")
                    new_thumb = upload_photo(profile_id, img_bytes, "thumb")
                    cur.execute(
                        "update public.photos set storage_path_full = %s, storage_path_thumb = %s, "
                        "moderation_status = 'approved' where id = %s",
                        (new_full, new_thumb, photo_id),
                    )
                    delete_old_object(old_full)
                    delete_old_object(old_thumb)
                    print(f"  position {position}: {file_path.name} yüklendi")

        conn.commit()
        print("\nTamamlandı.")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
