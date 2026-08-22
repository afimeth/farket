"""
Bot/test hesabi seed scripti — emulator uzerinden manuel test icin, gercek
kullanicinin (Test/testkullanici1) kesfedebilecegi, quiz cozebilecegi,
mesajlasabilecegi birden fazla yayinlanmis profil olusturur.

Wizard'i her hesap icin elle 9 adimda gecmek yerine (token/zaman acisindan
pahali), Admin API (auth.users) + Storage API (placeholder foto) + dogrudan
SQL (profiles/identity_card/profile_template_answers/custom_questions) ile
publish_profile()'in gerektirdigi TUM kosullari (5-7 foto, >=7 act1 kalip
cevap + zorluk dagilimi, >=2 act2 zor kalip cevap, >=1 dogru isaretli serbest
soru, username, age_attested_at, identity_card) karsilayarak profili
DOGRUDAN 'published' olarak insert eder.

Kullanim (yerel, varsayilan):
  python supabase/scripts/seed_bot_profiles.py

Kullanim (Supabase Cloud — DIKKAT: service_role/secret key ve DB sifresi
gerektirir, bu betigi Cloud'a karsi SADECE KENDI MAKINENDE, kendi
kimlik bilgilerinle calistir; bu ikisini hicbir AI asistanina/sohbete
YAPISTIRMA):
  python supabase/scripts/seed_bot_profiles.py \
    --api-url https://<project-ref>.supabase.co \
    --db-url "postgresql://postgres:<DB-SIFREN>@db.<project-ref>.supabase.co:5432/postgres" \
    --service-role-key <secret-key-Settings-API-Keys-sayfasindan>

Onkosul (yerel): `supabase start` calisir durumda, local stack ayakta.
"""
import argparse
import io
import random
import uuid
from pathlib import Path

import psycopg2
import requests
from PIL import Image, ImageDraw, ImageFont

DEFAULT_API_URL = "http://127.0.0.1:54321"
DEFAULT_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
DEFAULT_SERVICE_ROLE_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0."
    "EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", default=DEFAULT_API_URL, help="Supabase API URL (varsayilan: yerel)")
    parser.add_argument("--db-url", default=DEFAULT_DB_URL, help="Postgres baglanti string'i (varsayilan: yerel)")
    parser.add_argument(
        "--service-role-key", default=DEFAULT_SERVICE_ROLE_KEY,
        help="service_role/secret key (varsayilan: yerel demo anahtar)",
    )
    return parser.parse_args()


_ARGS = parse_args()
API_URL = _ARGS.api_url
DB_URL = _ARGS.db_url
SERVICE_ROLE_KEY = _ARGS.service_role_key
CITY_ID = 34  # İstanbul — gerçek test hesabıyla (account 1) aynı şehir seçilmeli
PROJECT_ROOT = Path(__file__).resolve().parents[2]

# Bot basina uretilecek kalip cevabi sayilari. Bir quiz 5 act1 + 2 act2-zor soru
# tuketiyor; havuz bunun epeyce ustunde tutuluyor ki ikinci/ucuncu quiz turunda
# gosterilecek YENI soru kalsin (start_quiz gorulmemis sorulari one aliyor).
# Ust sinirlar veritabanindaki aktif kalip sayilari: 48 kolay / 80 orta / 20 act2-zor.
EASY_ANSWER_COUNT = 14
MEDIUM_ANSWER_COUNT = 16
HARD_ANSWER_COUNT = 10

# Serbest sorular. get_quiz_allowance'in "profilin tam" kosulu en az 5 aktif
# serbest soru istiyor; ayrica her turda farkli bir serbest soru cikabilsin diye
# birden fazla tanimli. {name} bot adiyla degistiriliyor.
CUSTOM_QUESTION_BANK = [
    ("{name} en sevdiği tatili nerede geçirir?", ["Deniz kenarında", "Dağ evinde", "Şehir turunda"]),
    ("{name} sabahları önce ne yapar?", ["Kahve içer", "Müzik açar", "Telefona bakar"]),
    ("{name} hafta sonu planını nasıl yapar?", ["Önceden planlar", "Anlık karar verir", "Arkadaşlarına bırakır"]),
    ("{name} için akşam yemeği neyle tamamlanır?", ["Tatlıyla", "Uzun sohbetle", "Bir dizi bölümüyle"]),
    ("{name} yeni bir şehirde ilk nereye gider?", ["Bir kafeye", "Müzeye", "Yürüyüşe"]),
    ("{name} en çok neye zaman ayırır?", ["Spora", "Okumaya", "Arkadaşlarına"]),
]

# identity_card.intent CHECK constraint yalnızca bu iki değeri kabul ediyor
# ('arkadaslik' / 'flort' — bkz. 20260821150000_intent_friendship_flort.sql).
BOTS = [
    {"username": "elifyzmn", "display_name": "Elif", "sex": "female", "birth_date": "1998-03-12",
     "occupation": "Grafik tasarımcı", "intent": "arkadaslik"},
    {"username": "kaanaydemir", "display_name": "Kaan", "sex": "male", "birth_date": "1996-07-24",
     "occupation": "Yazılım mühendisi", "intent": "flort"},
    {"username": "zeynepklc", "display_name": "Zeynep", "sex": "female", "birth_date": "1999-11-02",
     "occupation": "Diş hekimi", "intent": "arkadaslik"},
    {"username": "emrekorkmaz", "display_name": "Emre", "sex": "male", "birth_date": "1995-01-30",
     "occupation": "Öğretmen", "intent": "flort"},
    {"username": "selinarslan", "display_name": "Selin", "sex": "female", "birth_date": "1997-05-18",
     "occupation": "Pazarlama uzmanı", "intent": "arkadaslik"},
    {"username": "burakdemirtas", "display_name": "Burak", "sex": "male", "birth_date": "1994-09-09",
     "occupation": "Fizyoterapist", "intent": "flort"},
]

AVATAR_COLORS = [
    (230, 126, 34), (41, 128, 185), (142, 68, 173), (39, 174, 96),
    (192, 57, 43), (211, 84, 0), (22, 160, 133), (44, 62, 80),
]


def admin_headers():
    return {"apikey": SERVICE_ROLE_KEY, "Authorization": f"Bearer {SERVICE_ROLE_KEY}"}


def create_auth_user(username: str) -> str:
    email = f"{username}@bot.farket.local"
    resp = requests.post(
        f"{API_URL}/auth/v1/admin/users",
        headers=admin_headers(),
        json={"email": email, "password": uuid.uuid4().hex, "email_confirm": True},
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()["id"]


AI_FACES_DIR = PROJECT_ROOT / "supabase" / "content-source" / "ai_faces"
BOT_PHOTOS_DIR = PROJECT_ROOT / "supabase" / "content-source" / "bot_photos"


def bot_photo_count(username: str) -> int:
    """bot_photos/<username>/ altındaki sıralı foto sayısı (yoksa 0)."""
    person_dir = BOT_PHOTOS_DIR / username
    if not person_dir.exists():
        return 0
    return len(list(person_dir.glob("*.png")))


def ai_face_bytes(username: str, position: int) -> tuple[bytes, str] | None:
    """Önce bot_photos/<username>/<n>.png (Downloads'tan kopyalanan gerçek kişi fotoğrafları),
    yoksa download_ai_faces.py ile indirilmiş <n>.jpg, yoksa None döner."""
    bot_path = BOT_PHOTOS_DIR / username / f"{position}.png"
    if bot_path.exists():
        return bot_path.read_bytes(), "png"
    ai_path = AI_FACES_DIR / username / f"{position}.jpg"
    if ai_path.exists():
        return ai_path.read_bytes(), "jpg"
    return None


def make_placeholder_image(display_name: str, seed_index: int) -> bytes:
    color = AVATAR_COLORS[seed_index % len(AVATAR_COLORS)]
    img = Image.new("RGB", (640, 640), color=color)
    draw = ImageDraw.Draw(img)
    initial = display_name[0].upper()
    try:
        font = ImageFont.truetype("arial.ttf", 260)
    except OSError:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), initial, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((640 - w) / 2 - bbox[0], (640 - h) / 2 - bbox[1]), initial, fill="white", font=font)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def upload_photo(profile_id: str, image_bytes: bytes, suffix: str, extension: str = "png") -> str:
    content_type = "image/jpeg" if extension == "jpg" else "image/png"
    object_name = f"{profile_id}/{uuid.uuid4()}_{suffix}.{extension}"
    resp = requests.post(
        f"{API_URL}/storage/v1/object/profile-photos/{object_name}",
        headers={**admin_headers(), "Content-Type": content_type},
        data=image_bytes,
        timeout=10,
    )
    resp.raise_for_status()
    return object_name


def sql_literal(value) -> str:
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def build_sql_for_bot(bot: dict, profile_id: str, photo_paths: list[tuple[str, str]]) -> str:
    stmts = []
    stmts.append(f"""
insert into public.profiles
  (id, display_name, birth_date, sex, city_id, status, username, age_attested_at, phone_verified_at, is_bot)
values
  ({sql_literal(profile_id)}, {sql_literal(bot['display_name'])}, {sql_literal(bot['birth_date'])},
   {sql_literal(bot['sex'])}, {CITY_ID}, 'draft', {sql_literal(bot['username'])}, now(), now(), true);
""")

    stmts.append(f"""
insert into public.identity_card
  (profile_id, show_name, show_age, show_occupation, show_city, show_intent, occupation, intent)
values
  ({sql_literal(profile_id)}, true, true, true, true, true,
   {sql_literal(bot['occupation'])}, {sql_literal(bot['intent'])});
""")

    # Kunye bilgileri. En az bir tanesi is_quiz_eligible OLMAK ZORUNDA: start_quiz'in
    # 2. perdesi (bkz. 20260821060000_start_quiz_two_phase) kunyeden otomatik soru
    # uretiyor ve hicbiri yoksa 'Hedef profilin quiz icin isaretlenmis kunye bilgisi
    # yok' diye patliyor. Bu betik profile_identity_attributes tablosundan onceydi,
    # bu yuzden uretilen botlarin quizi hic baslatilamiyordu.
    # is_quiz_eligible yalnizca sayisal alanlarda serbest (height_cm/weight_kg/age).
    height_cm = random.randint(158, 192)
    weight_kg = random.randint(50, 92)
    stmts.append(f"""
insert into public.profile_identity_attributes
  (profile_id, attribute_type, value_numeric, is_shown_on_reveal, is_quiz_eligible)
values
  ({sql_literal(profile_id)}, 'height_cm', {height_cm}, true, true),
  ({sql_literal(profile_id)}, 'weight_kg', {weight_kg}, true, true);
""")
    stmts.append(f"""
insert into public.profile_identity_attributes
  (profile_id, attribute_type, value_text, is_shown_on_reveal, is_quiz_eligible)
values
  ({sql_literal(profile_id)}, 'job', {sql_literal(bot['occupation'])}, true, false),
  ({sql_literal(profile_id)}, 'intent', {sql_literal(bot['intent'])}, true, false);
""")

    for position, (thumb_path, full_path) in enumerate(photo_paths, start=1):
        stmts.append(f"""
insert into public.photos (id, profile_id, position, storage_path_full, storage_path_thumb, contains_other_people, moderation_status)
values (gen_random_uuid(), {sql_literal(profile_id)}, {position}, {sql_literal(full_path)}, {sql_literal(thumb_path)}, false, 'approved');
""")

    # Kalip cevaplari artik sabit bir listeden (3 kolay + 4 orta + 2 zor) degil,
    # veritabanindaki havuzdan rastgele secilerek uretiliyor.
    #
    # Neden: eski hali botun toplam soru havuzunu 10 soruluk quizle neredeyse birebir
    # esitliyordu. Bu yuzden ikinci bir quiz turunda gosterilecek YENI soru kalmiyor,
    # start_quiz'in "daha once gorulmemis sorulari one al" davranisi test edilemiyordu.
    # Havuz genis olunca gercek kullanim kosullari taklit edilmis oluyor.
    #
    # Yalnizca taxonomy_id'si NULL olan kaliplar kullaniliyor: taksonomi tabanlilar
    # selected_item_id istiyor ve tohumlama icin gereksiz karmasiklik.
    stmts.append(f"""
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select {sql_literal(profile_id)}, qt.id,
       (select tpo.id from public.template_options tpo where tpo.template_id = qt.id order by random() limit 1),
       qt.default_difficulty
  from public.question_templates qt
 where qt.act = 1 and qt.is_active and qt.taxonomy_id is null
   and qt.default_difficulty = 'easy'
   and exists (select 1 from public.template_options tpo where tpo.template_id = qt.id)
 order by random() limit {EASY_ANSWER_COUNT};
""")
    stmts.append(f"""
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select {sql_literal(profile_id)}, qt.id,
       (select tpo.id from public.template_options tpo where tpo.template_id = qt.id order by random() limit 1),
       qt.default_difficulty
  from public.question_templates qt
 where qt.act = 1 and qt.is_active and qt.taxonomy_id is null
   and qt.default_difficulty = 'medium'
   and exists (select 1 from public.template_options tpo where tpo.template_id = qt.id)
 order by random() limit {MEDIUM_ANSWER_COUNT};
""")
    stmts.append(f"""
insert into public.profile_template_answers (profile_id, template_id, selected_option_id, difficulty)
select {sql_literal(profile_id)}, qt.id,
       (select tpo.id from public.template_options tpo where tpo.template_id = qt.id order by random() limit 1),
       'hard'
  from public.question_templates qt
 where qt.act = 2 and qt.is_active and qt.taxonomy_id is null
   and qt.default_difficulty = 'hard'
   and exists (select 1 from public.template_options tpo where tpo.template_id = qt.id)
 order by random() limit {HARD_ANSWER_COUNT};
""")

    # Birden fazla serbest soru: get_quiz_allowance'in "profilin tam" kosulu da
    # en az 5 aktif serbest soru istiyor, tek soru hem o kosulu hem tur cesitliligini
    # karsilamiyordu.
    for body, options in CUSTOM_QUESTION_BANK:
        question_id = str(uuid.uuid4())
        option_ids = [str(uuid.uuid4()) for _ in options]
        values = ",\n  ".join(
            f"({sql_literal(oid)}, {sql_literal(question_id)}, {sql_literal(text)}, {i})"
            for i, (oid, text) in enumerate(zip(option_ids, options), start=1)
        )
        stmts.append(f"""
insert into public.custom_questions (id, profile_id, body, is_active)
values ({sql_literal(question_id)}, {sql_literal(profile_id)}, {sql_literal(body.format(name=bot['display_name']))}, true);
insert into public.custom_options (id, question_id, body, position) values
  {values};
update public.custom_questions set correct_option_id = {sql_literal(random.choice(option_ids))} where id = {sql_literal(question_id)};
""")

    stmts.append(f"update public.profiles set status = 'published' where id = {sql_literal(profile_id)};")
    return "\n".join(stmts)


def run_sql(sql_text: str):
    conn = psycopg2.connect(DB_URL)
    try:
        conn.autocommit = False
        with conn.cursor() as cur:
            cur.execute(sql_text)
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def main():
    print(f"{len(BOTS)} bot hesabı oluşturulacak (şehir: İstanbul, id={CITY_ID})...")
    for i, bot in enumerate(BOTS):
        print(f"  -> @{bot['username']} ({bot['display_name']})")
        profile_id = create_auth_user(bot["username"])

        photo_paths = []
        photo_total = min(6, max(5, bot_photo_count(bot["username"])))
        for p in range(photo_total):
            real_face = ai_face_bytes(bot["username"], p + 1)
            if real_face is not None:
                img_bytes, extension = real_face
            else:
                img_bytes, extension = make_placeholder_image(bot["display_name"], i * 5 + p), "png"
            thumb = upload_photo(profile_id, img_bytes, "thumb", extension)
            full = upload_photo(profile_id, img_bytes, "full", extension)
            photo_paths.append((thumb, full))

        sql = build_sql_for_bot(bot, profile_id, photo_paths)
        run_sql(sql)
        print(f"     profile_id={profile_id} yayınlandı.")

    print("Tamamlandı. Discovery ekranında görmek için hesabınızın da 'İstanbul' şehrinde olması gerekir.")


if __name__ == "__main__":
    main()
