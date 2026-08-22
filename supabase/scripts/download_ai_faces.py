"""
Bot profilleri icin fotograf indirir — placeholder yerine gercekci gorunen,
randomuser.me servisinden (test/demo verisi icin hazirlanmis stok model
fotograflari, API her kaydin yasini `dob.age` ile bildiriyor).

thispersondoesnotexist.com gibi filtresiz StyleGAN uretimi KULLANILMIYOR:
o servis yas kontrolu yapmadigi icin cocuk gorunumlu goruntu doner (bir
seferinde denendi, sonuc silindi). randomuser.me ise kure edilmis, yetiskin
stok fotograflardan olusuyor; yine de indirilen her kayit `dob.age >= 18`
kontrolunden geciriliyor, gecmezse atlanip yerine yenisi istenir.

Kullanim:
  python supabase/scripts/download_ai_faces.py

Cikti: supabase/content-source/ai_faces/<username>/1.jpg ... 5.jpg
seed_bot_profiles.py bu klasoru bulursa PIL placeholder yerine bunlari kullanir.
"""
from pathlib import Path

import requests

API_URL = "https://randomuser.me/api/"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = PROJECT_ROOT / "supabase" / "content-source" / "ai_faces"
MIN_AGE = 18

# seed_bot_profiles.py'deki BOTS listesiyle ayni kullanici adi + cinsiyet.
BOTS = [
    ("elifyzmn", "female"),
    ("kaanaydemir", "male"),
    ("zeynepklc", "female"),
    ("emrekorkmaz", "male"),
    ("selinarslan", "female"),
    ("burakdemirtas", "male"),
]

PER_BOT = 5


def fetch_adult_photo_url(gender: str, used_urls: set[str]) -> str:
    """dob.age >= 18 ve istenen cinsiyette, daha önce kullanılmamış bir randomuser.me
    kaydının büyük fotoğraf URL'sini döner.

    Not: `seed` parametresi randomuser.me'de `gender` filtresini eziyor (API kusuru) —
    ilk denemede kadın botlara erkek fotoğrafı geldiği fark edildi. Bu yüzden seed
    KULLANILMIYOR; her istek doğal olarak rastgele ve gender/age sonrasında ayrıca
    doğrulanıyor.
    """
    for _ in range(10):
        resp = requests.get(API_URL, params={"gender": gender, "nat": "TR,US,GB,DE,FR"}, timeout=15)
        resp.raise_for_status()
        result = resp.json()["results"][0]
        url = result["picture"]["large"]
        if result["gender"] == gender and result["dob"]["age"] >= MIN_AGE and url not in used_urls:
            used_urls.add(url)
            return url
    raise RuntimeError(f"10 denemede uygun bir kayıt bulunamadı (gender={gender})")


def main() -> None:
    for username, gender in BOTS:
        folder = OUTPUT_DIR / username
        folder.mkdir(parents=True, exist_ok=True)
        used_urls: set[str] = set()
        print(f"@{username} ({gender}) için {PER_BOT} foto indiriliyor...")
        for i in range(1, PER_BOT + 1):
            dest = folder / f"{i}.jpg"
            if dest.exists():
                print(f"  {dest.name} zaten var, atlanıyor")
                continue
            url = fetch_adult_photo_url(gender, used_urls)
            img_resp = requests.get(url, timeout=15)
            img_resp.raise_for_status()
            dest.write_bytes(img_resp.content)
            print(f"  {dest.name} indirildi ({url})")

    print(f"\nTamamlandı. Fotoğraflar: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
