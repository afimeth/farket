-- Farket: production kalip/taksonomi seed'i (Gorev 1).
-- Kaynak: kullanicinin paylastigi farket-seed-data.json (140 sabit sikli
-- kalip soru + 8 taksonomi havuzu, 98 madde, 434 yonlu komsuluk kaydi).
-- Bu, supabase/seed.sql'deki yerel test fixture'indan AYRI, uzak
-- veritabanina da gidecek gercek bir migration -- brifing v3'un
-- talimatiyla birebir uyumlu.
--
-- Idempotent: code (question_templates, taxonomies) ve
-- (taxonomy_id, label) (taxonomy_items) dogal anahtarlar uzerinden
-- ON CONFLICT DO UPDATE/NOTHING kullaniliyor. Metin duzeltmeleri icin
-- gelecekte bu migration'in guncellenmis JSON'la yeniden yazilmasi
-- (ya da ayni deseni kullanan yeni bir migration) guvenli sekilde
-- calisir.
--
-- template_stats bu asamada DOLDURULMUYOR -- taban oran verisi gercek
-- kullanimdan gelecek.

create temp table _seed_json as
select $farket_seed${
  "_meta": {
    "surum": "1.0",
    "aciklama": "Farket production seed verisi. question_templates/template_options ve taxonomies/taxonomy_items/taxonomy_adjacency tablolarına yuklenecek.",
    "notlar": [
      "code alanlari dogal anahtardir; tekrar calistirmada upsert icin kullanilabilir.",
      "act 1 sorulari 3 sikli, act 2 sorulari 4 siklidir.",
      "Taksonomi komsuluklari cift yonlu kaydedilmelidir (A->B ve B->A).",
      "Taksonomi sorulari question_templates icinde taxonomy_code ile iliskilendirilir, template_options bos kalir.",
      "Taksonomi sorularinin zorlugu kullanici tarafindan secilir; default_difficulty medium."
    ]
  },
  "question_templates": [
    {
      "code": "tarz_01",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Tarzım hangisine daha yakın?",
      "options": [
        "Sade ve minimal",
        "Sokak stili",
        "Klasik ve derli toplu"
      ]
    },
    {
      "code": "tarz_02",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Gardırobumda en çok hangi renk var?",
      "options": [
        "Siyah-gri tonları",
        "Toprak tonları",
        "Canlı renkler"
      ]
    },
    {
      "code": "tarz_03",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Genelde ne giyerim?",
      "options": [
        "Oversize ve rahat",
        "Vücuda oturan",
        "Spor giyim"
      ]
    },
    {
      "code": "tarz_04",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Ayakkabı tercihim?",
      "options": [
        "Spor ayakkabı",
        "Bot",
        "Klasik"
      ]
    },
    {
      "code": "tarz_05",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Aksesuar kullanır mıyım?",
      "options": [
        "Hiç takmam",
        "Bir iki parça",
        "Bolca takarım"
      ]
    },
    {
      "code": "tarz_06",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Saç konusunda ben?",
      "options": [
        "Yıllardır aynı",
        "Sık sık değiştiririm",
        "Uzatıyorum"
      ]
    },
    {
      "code": "tarz_07",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Dövmem var mı?",
      "options": [
        "Yok",
        "Bir iki tane",
        "Epeyce"
      ]
    },
    {
      "code": "tarz_08",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Gözlük durumum?",
      "options": [
        "Takmam",
        "Numaralı gözlük",
        "Lens kullanırım"
      ]
    },
    {
      "code": "tarz_09",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sabah hazırlanmam ne kadar sürer?",
      "options": [
        "10 dakikadan az",
        "Yarım saat",
        "Bir saatten fazla"
      ]
    },
    {
      "code": "tarz_10",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Çanta tercihim?",
      "options": [
        "Sırt çantası",
        "Omuz çantası",
        "Hiçbiri, ceplerim yeter"
      ]
    },
    {
      "code": "tarz_11",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Tarzımı en çok ne belirler?",
      "options": [
        "Rahatlık",
        "Görünüş",
        "İkisi de eşit"
      ]
    },
    {
      "code": "tarz_12",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Alışverişimi nereden yaparım?",
      "options": [
        "Zincir mağazalar",
        "İkinci el ve vintage",
        "Online"
      ]
    },
    {
      "code": "mekan_01",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Buluşma yeri seçsem neresi olur?",
      "options": [
        "Kafe",
        "Bar veya mekan",
        "Açık hava"
      ]
    },
    {
      "code": "mekan_02",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Hafta sonu beni nerede bulursun?",
      "options": [
        "Dışarıda, sürekli hareket",
        "Evde",
        "Yarı yarıya"
      ]
    },
    {
      "code": "mekan_03",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Kalabalık ortamlarda ben?",
      "options": [
        "Enerji alırım",
        "Çabuk yorulurum",
        "Duruma göre"
      ]
    },
    {
      "code": "mekan_04",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Gece hayatı bende?",
      "options": [
        "Neredeyse hiç",
        "Ara sıra",
        "Düzenli"
      ]
    },
    {
      "code": "mekan_05",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Kafede oturunca?",
      "options": [
        "Saatlerce kalırım",
        "İçip çıkarım",
        "Çalışmaya giderim"
      ]
    },
    {
      "code": "mekan_06",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Konser ve festival?",
      "options": [
        "Kaçırmam",
        "Ara sıra",
        "Bana göre değil"
      ]
    },
    {
      "code": "mekan_07",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Şehirde en sevdiğim yer tipi?",
      "options": [
        "Tarihi semtler",
        "Modern merkezler",
        "Şehir dışı"
      ]
    },
    {
      "code": "mekan_08",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Kütüphane mi kafe mi?",
      "options": [
        "Kütüphane",
        "Kafe",
        "Ev"
      ]
    },
    {
      "code": "mekan_09",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sinemaya gitme sıklığım?",
      "options": [
        "Sık sık",
        "Nadiren",
        "Evde izlemeyi tercih ederim"
      ]
    },
    {
      "code": "mekan_10",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Müze ve sergi?",
      "options": [
        "İlgimi çeker",
        "Fena değil",
        "Pek değil"
      ]
    },
    {
      "code": "mekan_11",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Plaj mı dağ mı?",
      "options": [
        "Plaj",
        "Dağ",
        "İkisi de olur"
      ]
    },
    {
      "code": "mekan_12",
      "category": "mekan",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yalnız kahve içmeye çıkar mıyım?",
      "options": [
        "Sürekli",
        "Bazen",
        "Hiç"
      ]
    },
    {
      "code": "muzik_01",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "En çok dinlediğim tür?",
      "options": [
        "Rock ve türevleri",
        "Rap ve hip-hop",
        "Elektronik"
      ]
    },
    {
      "code": "muzik_02",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Enstrüman çalar mıyım?",
      "options": [
        "Çalarım",
        "Denedim, bıraktım",
        "Hiç"
      ]
    },
    {
      "code": "muzik_03",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Müzik dinleme şeklim?",
      "options": [
        "Kulaklıkla, sürekli",
        "Ortam müziği gibi",
        "Az dinlerim"
      ]
    },
    {
      "code": "muzik_04",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Konserde nerede olurum?",
      "options": [
        "En önde",
        "Ortalarda",
        "Arkada, rahat"
      ]
    },
    {
      "code": "muzik_05",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Türkçe müzik mi yabancı mı?",
      "options": [
        "Türkçe ağırlıklı",
        "Yabancı ağırlıklı",
        "Karışık"
      ]
    },
    {
      "code": "muzik_06",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Plak veya kaset ilgim?",
      "options": [
        "Koleksiyonum var",
        "İlgimi çeker",
        "Dijital yeter"
      ]
    },
    {
      "code": "muzik_07",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Çalışırken müzik?",
      "options": [
        "Şart",
        "Sözsüz olmalı",
        "Sessizlik isterim"
      ]
    },
    {
      "code": "muzik_08",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Karaoke?",
      "options": [
        "Bayılırım",
        "Israr edilirse",
        "Asla"
      ]
    },
    {
      "code": "muzik_09",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yeni müzik keşfi?",
      "options": [
        "Sürekli ararım",
        "Önerilerle",
        "Aynı şeyleri dinlerim"
      ]
    },
    {
      "code": "muzik_10",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Festival deneyimim?",
      "options": [
        "Birkaç kez gittim",
        "Bir kez",
        "Hiç"
      ]
    },
    {
      "code": "muzik_11",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Müzikte dönem tercihim?",
      "options": [
        "Eski, nostaljik",
        "Güncel",
        "Fark etmez"
      ]
    },
    {
      "code": "muzik_12",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Sahne almışlığım var mı?",
      "options": [
        "Var",
        "Yok ama isterim",
        "Asla istemem"
      ]
    },
    {
      "code": "spor_01",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Düzenli spor yapar mıyım?",
      "options": [
        "Haftada birkaç kez",
        "Ara sıra",
        "Hiç"
      ]
    },
    {
      "code": "spor_02",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Spor tercihim?",
      "options": [
        "Ağırlık ve fitness",
        "Takım sporu",
        "Koşu ve dayanıklılık"
      ]
    },
    {
      "code": "spor_03",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Takım sporu oynar mıyım?",
      "options": [
        "Düzenli oynarım",
        "Bazen",
        "Seyrederim sadece"
      ]
    },
    {
      "code": "spor_04",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Sahada mevkiim?",
      "options": [
        "Defans",
        "Orta saha",
        "Forvet veya kaleci"
      ]
    },
    {
      "code": "spor_05",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Doğa yürüyüşü?",
      "options": [
        "Düzenli yaparım",
        "Denedim",
        "Bana göre değil"
      ]
    },
    {
      "code": "spor_06",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Bisiklet?",
      "options": [
        "Ulaşım aracım",
        "Keyif için",
        "Kullanmam"
      ]
    },
    {
      "code": "spor_07",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Su sporları?",
      "options": [
        "İlgim var",
        "Denedim",
        "Hiç"
      ]
    },
    {
      "code": "spor_08",
      "category": "spor",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sabah sporu mu akşam sporu mu?",
      "options": [
        "Sabah",
        "Akşam",
        "Düzenim yok"
      ]
    },
    {
      "code": "spor_09",
      "category": "spor",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Maç izleme alışkanlığım?",
      "options": [
        "Kaçırmam",
        "Büyük maçlar",
        "İzlemem"
      ]
    },
    {
      "code": "spor_10",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Kayak veya snowboard?",
      "options": [
        "Yaparım",
        "Denemek isterim",
        "İlgim yok"
      ]
    },
    {
      "code": "spor_11",
      "category": "spor",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Yoga veya pilates?",
      "options": [
        "Düzenli",
        "Denedim",
        "Hiç"
      ]
    },
    {
      "code": "spor_12",
      "category": "spor",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Spor benim için?",
      "options": [
        "Disiplin",
        "Sosyalleşme",
        "Kafa dağıtma"
      ]
    },
    {
      "code": "yeme_01",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Günün ilk içeceği?",
      "options": [
        "Türk kahvesi",
        "Filtre veya espresso",
        "Çay"
      ]
    },
    {
      "code": "yeme_02",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Kahve mi çay mı?",
      "options": [
        "Kahve",
        "Çay",
        "İkisi de"
      ]
    },
    {
      "code": "yeme_03",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yemek yapar mıyım?",
      "options": [
        "Sık sık",
        "Ara sıra",
        "Neredeyse hiç"
      ]
    },
    {
      "code": "yeme_04",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Dışarıda yemek sıklığım?",
      "options": [
        "Çoğu öğün",
        "Haftada birkaç",
        "Nadiren"
      ]
    },
    {
      "code": "yeme_05",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Et yer miyim?",
      "options": [
        "Yerim",
        "Az yerim",
        "Vejetaryen veya vegan"
      ]
    },
    {
      "code": "yeme_06",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Tatlı tercihim?",
      "options": [
        "Şerbetli",
        "Sütlü",
        "Tatlı sevmem"
      ]
    },
    {
      "code": "yeme_07",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Kahvaltı?",
      "options": [
        "Uzun ve keyifli",
        "Hızlı",
        "Yapmam"
      ]
    },
    {
      "code": "yeme_08",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Baharat ve acı?",
      "options": [
        "Acı severim",
        "Ortası",
        "Hiç sevmem"
      ]
    },
    {
      "code": "yeme_09",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sokak lezzetleri mi restoran mı?",
      "options": [
        "Sokak",
        "Restoran",
        "İkisi de"
      ]
    },
    {
      "code": "yeme_10",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Alkol kullanır mıyım?",
      "options": [
        "Kullanmam",
        "Sosyal ortamlarda",
        "Düzenli"
      ]
    },
    {
      "code": "yeme_11",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Sigara?",
      "options": [
        "İçmem",
        "Sosyal",
        "Düzenli"
      ]
    },
    {
      "code": "yeme_12",
      "category": "yeme_icme",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yeni mutfaklar denemek?",
      "options": [
        "Bayılırım",
        "Ara sıra",
        "Bildiğimi yerim"
      ]
    },
    {
      "code": "seyahat_01",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Tatilde ne yaparım?",
      "options": [
        "Gezerim, durmam",
        "Dinlenirim",
        "Karışık"
      ]
    },
    {
      "code": "seyahat_02",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Kamp yapar mıyım?",
      "options": [
        "Düzenli",
        "Bir iki kez",
        "Hiç"
      ]
    },
    {
      "code": "seyahat_03",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Yurt dışı deneyimim?",
      "options": [
        "Birçok ülke",
        "Birkaç kez",
        "Hiç"
      ]
    },
    {
      "code": "seyahat_04",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Seyahat planlaması?",
      "options": [
        "Detaylı planlarım",
        "Kabaca",
        "Hiç planlamam"
      ]
    },
    {
      "code": "seyahat_05",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yalnız seyahat?",
      "options": [
        "Yaptım, severim",
        "Denemek isterim",
        "Bana göre değil"
      ]
    },
    {
      "code": "seyahat_06",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Ulaşım tercihim?",
      "options": [
        "Uçak",
        "Otobüs veya tren",
        "Kendi aracım"
      ]
    },
    {
      "code": "seyahat_07",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Konaklama?",
      "options": [
        "Otel",
        "Hostel veya pansiyon",
        "Kamp veya arkadaş evi"
      ]
    },
    {
      "code": "seyahat_08",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Deniz mi göl mü?",
      "options": [
        "Deniz",
        "Göl ve nehir",
        "Havuz"
      ]
    },
    {
      "code": "seyahat_09",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Doğada gece kalır mıyım?",
      "options": [
        "Çadırda kalırım",
        "Bungalov tarzı",
        "Şehre dönerim"
      ]
    },
    {
      "code": "seyahat_10",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Fotoğraf çeker miyim?",
      "options": [
        "Sürekli",
        "Ara sıra",
        "Nadiren"
      ]
    },
    {
      "code": "seyahat_11",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yaz tatilim genelde?",
      "options": [
        "Aynı yere giderim",
        "Her yıl farklı",
        "Tatil yapmam"
      ]
    },
    {
      "code": "seyahat_12",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Balık tutmak?",
      "options": [
        "Yaparım",
        "Denedim",
        "Hiç"
      ]
    },
    {
      "code": "ev_01",
      "category": "ev",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Evimin hali?",
      "options": [
        "Toplu ve düzenli",
        "Yaşanmış, dağınık",
        "Ortası"
      ]
    },
    {
      "code": "ev_02",
      "category": "ev",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Evimde en çok ne var?",
      "options": [
        "Kitap",
        "Bitki",
        "Teknolojik eşya"
      ]
    },
    {
      "code": "ev_03",
      "category": "ev",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Dekorasyon tarzım?",
      "options": [
        "Minimal",
        "Dolu ve renkli",
        "Hiç uğraşmam"
      ]
    },
    {
      "code": "ev_04",
      "category": "ev",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Duvarımda ne asılı?",
      "options": [
        "Poster ve afiş",
        "Tablo veya fotoğraf",
        "Boş duvar"
      ]
    },
    {
      "code": "ev_05",
      "category": "ev",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Bitki bakar mıyım?",
      "options": [
        "Bir sürü var",
        "Bir iki tane",
        "Hiç"
      ]
    },
    {
      "code": "ev_06",
      "category": "ev",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Kitap okuma alışkanlığım?",
      "options": [
        "Düzenli",
        "Ara sıra",
        "Nadiren"
      ]
    },
    {
      "code": "ev_07",
      "category": "ev",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Kitap tercihim?",
      "options": [
        "Kurgu",
        "Kurgu dışı",
        "Çizgi roman veya grafik"
      ]
    },
    {
      "code": "ev_08",
      "category": "ev",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Oyun konsolu veya bilgisayar?",
      "options": [
        "Oyun oynarım",
        "Ara sıra",
        "Hiç"
      ]
    },
    {
      "code": "ev_09",
      "category": "ev",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Koleksiyon yapar mıyım?",
      "options": [
        "Yaparım",
        "Biriktiririm sayılır",
        "Hiç"
      ]
    },
    {
      "code": "ev_10",
      "category": "ev",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Ev mi dışarı mı?",
      "options": [
        "Ev insanıyım",
        "Dışarı insanıyım",
        "Dengeli"
      ]
    },
    {
      "code": "hayvan_01",
      "category": "hayvanlar",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Evcil hayvanım var mı?",
      "options": [
        "Kedi",
        "Köpek",
        "Yok"
      ]
    },
    {
      "code": "hayvan_02",
      "category": "hayvanlar",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Kedi mi köpek mi?",
      "options": [
        "Kedi",
        "Köpek",
        "İkisi de"
      ]
    },
    {
      "code": "hayvan_03",
      "category": "hayvanlar",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sokak hayvanlarıyla aram?",
      "options": [
        "Beslerim, ilgilenirim",
        "Severim ama uzaktan",
        "Mesafeliyim"
      ]
    },
    {
      "code": "hayvan_04",
      "category": "hayvanlar",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Hayvan sahiplenmek?",
      "options": [
        "Sahiplendim",
        "Düşünüyorum",
        "Bana göre değil"
      ]
    },
    {
      "code": "hayvan_05",
      "category": "hayvanlar",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Hayvanlarla fotoğraf?",
      "options": [
        "Bol bol var",
        "Bir iki",
        "Hiç"
      ]
    },
    {
      "code": "hayvan_06",
      "category": "hayvanlar",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Egzotik hayvan ilgim?",
      "options": [
        "Var",
        "Merak ederim",
        "Yok"
      ]
    },
    {
      "code": "hayvan_07",
      "category": "hayvanlar",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Hayvanlı bir mekan olsa?",
      "options": [
        "Bayılırım",
        "Fena değil",
        "Tercih etmem"
      ]
    },
    {
      "code": "hayvan_08",
      "category": "hayvanlar",
      "act": 1,
      "default_difficulty": "easy",
      "body": "At binmek?",
      "options": [
        "Bindim, severim",
        "Denemek isterim",
        "İlgim yok"
      ]
    },
    {
      "code": "sosyal_01",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Kalabalık grupta ben?",
      "options": [
        "Ortadayım",
        "Kenardayım",
        "Duruma göre"
      ]
    },
    {
      "code": "sosyal_02",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yeni insanlarla tanışmak?",
      "options": [
        "Kolay gelir",
        "Zaman alır",
        "Zorlanırım"
      ]
    },
    {
      "code": "sosyal_03",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Arkadaş çevrem?",
      "options": [
        "Geniş",
        "Küçük ama sıkı",
        "İkisi karışık"
      ]
    },
    {
      "code": "sosyal_04",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Planları kim yapar?",
      "options": [
        "Genelde ben",
        "Katılırım",
        "Son anda karar veririm"
      ]
    },
    {
      "code": "sosyal_05",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Fotoğrafta genelde?",
      "options": [
        "Yalnızım",
        "Kalabalıktayım",
        "İkisi de var"
      ]
    },
    {
      "code": "sosyal_06",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Doğum günümü?",
      "options": [
        "Kalabalık kutlarım",
        "Küçük grupla",
        "Kutlamam"
      ]
    },
    {
      "code": "sosyal_07",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Tartışmada ben?",
      "options": [
        "Fikrimi savunurum",
        "Dinlerim",
        "Konuyu değiştiririm"
      ]
    },
    {
      "code": "sosyal_08",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sosyal ortamda ilk saat?",
      "options": [
        "Hemen kaynarım",
        "Isınmam gerekir",
        "Bir köşede beklerim"
      ]
    },
    {
      "code": "sosyal_09",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Espri anlayışım?",
      "options": [
        "İğneleyici",
        "Absürt",
        "Yumuşak"
      ]
    },
    {
      "code": "sosyal_10",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Hediye seçerken?",
      "options": [
        "Uzun düşünürüm",
        "Pratik alırım",
        "Zorlanırım"
      ]
    },
    {
      "code": "sosyal_11",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Mesajlaşmada ben?",
      "options": [
        "Hızlı cevap",
        "Geç ama uzun",
        "Sesli mesaj"
      ]
    },
    {
      "code": "sosyal_12",
      "category": "sosyal",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Kavga sonrası ilk adım?",
      "options": [
        "Ben atarım",
        "Beklerim",
        "Konuyu kapatırım"
      ]
    },
    {
      "code": "rutin_01",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sabahçı mı gececi mi?",
      "options": [
        "Sabahçı",
        "Gececi",
        "Değişken"
      ]
    },
    {
      "code": "rutin_02",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Hafta içi akşamlarım?",
      "options": [
        "Dolu",
        "Sakin",
        "Değişir"
      ]
    },
    {
      "code": "rutin_03",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Planlı mıyım?",
      "options": [
        "Her şeyi planlarım",
        "Kabaca",
        "Akışına bırakırım"
      ]
    },
    {
      "code": "rutin_04",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Erken gelir miyim?",
      "options": [
        "Hep erken",
        "Tam vaktinde",
        "Genelde geç"
      ]
    },
    {
      "code": "rutin_05",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Boş zamanımda?",
      "options": [
        "Bir şeyler üretirim",
        "Dinlenirim",
        "Dışarı çıkarım"
      ]
    },
    {
      "code": "rutin_06",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Rutinlerim?",
      "options": [
        "Güçlü rutinlerim var",
        "Esnek",
        "Hiç yok"
      ]
    },
    {
      "code": "rutin_07",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Uyku düzenim?",
      "options": [
        "Düzenli",
        "Dağınık",
        "Az uyurum"
      ]
    },
    {
      "code": "rutin_08",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yeni bir şeye başlarken?",
      "options": [
        "Hemen atlarım",
        "Araştırırım",
        "Uzun düşünürüm"
      ]
    },
    {
      "code": "rutin_09",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Aynı anda kaç iş?",
      "options": [
        "Tek işe odaklanırım",
        "Birkaç iş birden",
        "Karışır"
      ]
    },
    {
      "code": "rutin_10",
      "category": "rutin",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yalnız kalma ihtiyacım?",
      "options": [
        "Yüksek",
        "Orta",
        "Düşük"
      ]
    },
    {
      "code": "dijital_01",
      "category": "dijital",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sosyal medyada ben?",
      "options": [
        "Aktif paylaşırım",
        "İzlerim, paylaşmam",
        "Neredeyse yokum"
      ]
    },
    {
      "code": "dijital_02",
      "category": "dijital",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Ekran süremle aram?",
      "options": [
        "Fazla, biliyorum",
        "Kontrollü",
        "Az"
      ]
    },
    {
      "code": "dijital_03",
      "category": "dijital",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Video oyunları?",
      "options": [
        "Düzenli oynarım",
        "Ara sıra",
        "Hiç"
      ]
    },
    {
      "code": "dijital_04",
      "category": "dijital",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Dizi izleme şeklim?",
      "options": [
        "Bir oturuşta bitiririm",
        "Bölüm bölüm",
        "Az izlerim"
      ]
    },
    {
      "code": "dijital_05",
      "category": "dijital",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Podcast veya sesli içerik?",
      "options": [
        "Düzenli dinlerim",
        "Ara sıra",
        "Hiç"
      ]
    },
    {
      "code": "dijital_06",
      "category": "dijital",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Telefonumun hali?",
      "options": [
        "Kırık veya yıpranmış",
        "Tertemiz",
        "Kılıflı, korumalı"
      ]
    },
    {
      "code": "dijital_07",
      "category": "dijital",
      "act": 1,
      "default_difficulty": "easy",
      "body": "Fotoğraf düzenler miyim?",
      "options": [
        "Detaylıca",
        "Hafif",
        "Hiç dokunmam"
      ]
    },
    {
      "code": "dijital_08",
      "category": "dijital",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Yeni teknoloji?",
      "options": [
        "Hemen denerim",
        "Beklerim",
        "İlgim yok"
      ]
    },
    {
      "code": "zor_01",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Bir hafta izin alsam ne yaparım?",
      "options": [
        "Uzak bir ülkeye giderim",
        "Evde hiçbir şey yapmam",
        "Kampa giderim",
        "Ailemin yanına giderim"
      ]
    },
    {
      "code": "zor_02",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "En çok neye kızarım?",
      "options": [
        "Geç kalınmasına",
        "Yalana",
        "Küçümsenmeye",
        "Kararsızlığa"
      ]
    },
    {
      "code": "zor_03",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Para biriktirir miyim?",
      "options": [
        "Titizlikle",
        "Denerim ama olmaz",
        "Harcarım",
        "Hiç düşünmem"
      ]
    },
    {
      "code": "zor_04",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Kendimi en çok nerede rahat hissederim?",
      "options": [
        "Kalabalıkta",
        "Yakın arkadaşlarımla",
        "Yalnızken",
        "Ailemle"
      ]
    },
    {
      "code": "zor_05",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "En büyük hayalim hangi alanda?",
      "options": [
        "Kariyer",
        "Seyahat",
        "Yaratıcı bir iş",
        "Sakin bir hayat"
      ]
    },
    {
      "code": "zor_06",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Karar verirken?",
      "options": [
        "Mantığıma",
        "Hislerime",
        "Başkasına danışırım",
        "Ertelerim"
      ]
    },
    {
      "code": "zor_07",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Beni en iyi hangisi anlatır?",
      "options": [
        "Meraklı",
        "Sadık",
        "İnatçı",
        "Rahat"
      ]
    },
    {
      "code": "zor_08",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Zor bir günün sonunda?",
      "options": [
        "Konuşurum",
        "Yalnız kalırım",
        "Dışarı çıkarım",
        "Uyurum"
      ]
    },
    {
      "code": "zor_09",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Beş yıl sonra kendimi nerede görüyorum?",
      "options": [
        "Aynı şehirde",
        "Başka şehirde",
        "Yurt dışında",
        "Hiç fikrim yok"
      ]
    },
    {
      "code": "zor_10",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Bana en çok ne söylenir?",
      "options": [
        "Çok sakinsin",
        "Çok enerjiksin",
        "Çok düşünüyorsun",
        "Çok konuşuyorsun"
      ]
    },
    {
      "code": "zor_11",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Risk almak?",
      "options": [
        "Severim",
        "Hesaplı alırım",
        "Kaçınırım",
        "Duruma göre"
      ]
    },
    {
      "code": "zor_12",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "En değer verdiğim şey?",
      "options": [
        "Özgürlük",
        "Güven",
        "Başarı",
        "Huzur"
      ]
    },
    {
      "code": "zor_13",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "İlk buluşma için ideal yer?",
      "options": [
        "Yürüyüş",
        "Kafe",
        "Bir etkinlik",
        "Yemek"
      ]
    },
    {
      "code": "zor_14",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Bir tartışmayı nasıl bitiririm?",
      "options": [
        "Özür dilerim",
        "Konuyu kapatırım",
        "Sonuna kadar giderim",
        "Uzaklaşırım"
      ]
    },
    {
      "code": "zor_15",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Hangisi bana daha yakın?",
      "options": [
        "Planlı yaşam",
        "Spontane yaşam",
        "Ortası",
        "Duruma göre"
      ]
    },
    {
      "code": "zor_16",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "En zorlandığım şey?",
      "options": [
        "Hayır demek",
        "Duygularımı anlatmak",
        "Beklemek",
        "Rutine girmek"
      ]
    },
    {
      "code": "zor_17",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Yeni bir şehre taşınmak?",
      "options": [
        "Hemen yaparım",
        "Uzun düşünürüm",
        "İstemem",
        "Zaten yaptım"
      ]
    },
    {
      "code": "zor_18",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Beni en çok ne motive eder?",
      "options": [
        "Merak",
        "Rekabet",
        "Onay",
        "Kendi hedeflerim"
      ]
    },
    {
      "code": "zor_19",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Arkadaşlıkta en önemlisi?",
      "options": [
        "Dürüstlük",
        "Sadakat",
        "Eğlence",
        "Anlayış"
      ]
    },
    {
      "code": "zor_20",
      "category": "zor",
      "act": 2,
      "default_difficulty": "hard",
      "body": "Hafta sonu sabahı?",
      "options": [
        "Erken kalkar plan yaparım",
        "Geç kalkarım",
        "Duruma göre",
        "Çalışırım"
      ]
    }
  ],
  "taxonomies": [
    {
      "code": "tarz",
      "question_body": "Sence tarzım aşağıdakilerden hangisine daha çok uyuyor?",
      "items": [
        {
          "label": "Sokak stili",
          "neighbors": [
            "Gece ve elektronik sahne",
            "Normcore",
            "Punk",
            "Rap ve hip-hop kültürü",
            "Sporcu"
          ]
        },
        {
          "label": "Minimalist",
          "neighbors": [
            "Akademik",
            "Klasik ve şık",
            "Normcore",
            "Sporcu"
          ]
        },
        {
          "label": "Klasik ve şık",
          "neighbors": [
            "Akademik",
            "Minimalist",
            "Normcore",
            "Vintage ve retro"
          ]
        },
        {
          "label": "Sporcu",
          "neighbors": [
            "Minimalist",
            "Normcore",
            "Outdoor ve doğa",
            "Rap ve hip-hop kültürü",
            "Sokak stili"
          ]
        },
        {
          "label": "Vintage ve retro",
          "neighbors": [
            "Akademik",
            "Alternatif ve indie",
            "Bohem",
            "Klasik ve şık",
            "Outdoor ve doğa",
            "Rock ve metal"
          ]
        },
        {
          "label": "Rock ve metal",
          "neighbors": [
            "Alternatif ve indie",
            "Gece ve elektronik sahne",
            "Punk",
            "Vintage ve retro"
          ]
        },
        {
          "label": "Punk",
          "neighbors": [
            "Alternatif ve indie",
            "Gece ve elektronik sahne",
            "Rap ve hip-hop kültürü",
            "Rock ve metal",
            "Sokak stili"
          ]
        },
        {
          "label": "Alternatif ve indie",
          "neighbors": [
            "Bohem",
            "Gece ve elektronik sahne",
            "Punk",
            "Rock ve metal",
            "Vintage ve retro"
          ]
        },
        {
          "label": "Bohem",
          "neighbors": [
            "Akademik",
            "Alternatif ve indie",
            "Outdoor ve doğa",
            "Vintage ve retro"
          ]
        },
        {
          "label": "Akademik",
          "neighbors": [
            "Bohem",
            "Klasik ve şık",
            "Minimalist",
            "Vintage ve retro"
          ]
        },
        {
          "label": "Gece ve elektronik sahne",
          "neighbors": [
            "Alternatif ve indie",
            "Punk",
            "Rap ve hip-hop kültürü",
            "Rock ve metal",
            "Sokak stili"
          ]
        },
        {
          "label": "Outdoor ve doğa",
          "neighbors": [
            "Bohem",
            "Normcore",
            "Sporcu",
            "Vintage ve retro"
          ]
        },
        {
          "label": "Normcore",
          "neighbors": [
            "Klasik ve şık",
            "Minimalist",
            "Outdoor ve doğa",
            "Sokak stili",
            "Sporcu"
          ]
        },
        {
          "label": "Rap ve hip-hop kültürü",
          "neighbors": [
            "Gece ve elektronik sahne",
            "Punk",
            "Sokak stili",
            "Sporcu"
          ]
        }
      ]
    },
    {
      "code": "muzik",
      "question_body": "En çok hangi türü dinlerim?",
      "items": [
        {
          "label": "Rock",
          "neighbors": [
            "Alternatif ve indie",
            "Metal",
            "Pop",
            "Punk"
          ]
        },
        {
          "label": "Metal",
          "neighbors": [
            "Alternatif ve indie",
            "Elektronik ve techno",
            "Punk",
            "Rock"
          ]
        },
        {
          "label": "Punk",
          "neighbors": [
            "Alternatif ve indie",
            "Metal",
            "Rap ve hip-hop",
            "Rock"
          ]
        },
        {
          "label": "Alternatif ve indie",
          "neighbors": [
            "Metal",
            "Pop",
            "Punk",
            "Rock"
          ]
        },
        {
          "label": "Rap ve hip-hop",
          "neighbors": [
            "Elektronik ve techno",
            "Pop",
            "Punk",
            "R&B ve soul"
          ]
        },
        {
          "label": "Elektronik ve techno",
          "neighbors": [
            "Metal",
            "Pop",
            "Rap ve hip-hop",
            "Reggae ve dub"
          ]
        },
        {
          "label": "Pop",
          "neighbors": [
            "Alternatif ve indie",
            "Arabesk",
            "Elektronik ve techno",
            "R&B ve soul",
            "Rap ve hip-hop",
            "Rock",
            "Türkçe pop"
          ]
        },
        {
          "label": "Türkçe pop",
          "neighbors": [
            "Arabesk",
            "Pop",
            "R&B ve soul",
            "Türk halk müziği"
          ]
        },
        {
          "label": "Arabesk",
          "neighbors": [
            "Klasik müzik",
            "Pop",
            "Türk halk müziği",
            "Türkçe pop"
          ]
        },
        {
          "label": "Türk halk müziği",
          "neighbors": [
            "Arabesk",
            "Jazz",
            "Klasik müzik",
            "Türkçe pop"
          ]
        },
        {
          "label": "Jazz",
          "neighbors": [
            "Klasik müzik",
            "R&B ve soul",
            "Reggae ve dub",
            "Türk halk müziği"
          ]
        },
        {
          "label": "Klasik müzik",
          "neighbors": [
            "Arabesk",
            "Jazz",
            "Reggae ve dub",
            "Türk halk müziği"
          ]
        },
        {
          "label": "R&B ve soul",
          "neighbors": [
            "Jazz",
            "Pop",
            "Rap ve hip-hop",
            "Reggae ve dub",
            "Türkçe pop"
          ]
        },
        {
          "label": "Reggae ve dub",
          "neighbors": [
            "Elektronik ve techno",
            "Jazz",
            "Klasik müzik",
            "R&B ve soul"
          ]
        }
      ]
    },
    {
      "code": "hafta_sonu",
      "question_body": "Hafta sonu beni en çok nerede bulursun?",
      "items": [
        {
          "label": "Doğa yürüyüşünde",
          "neighbors": [
            "Kampta",
            "Sahada spor yaparken",
            "Spor salonunda",
            "Yolculukta",
            "Şehirde amaçsız gezerken"
          ]
        },
        {
          "label": "Kampta",
          "neighbors": [
            "Doğa yürüyüşünde",
            "Sahada spor yaparken",
            "Yolculukta",
            "Şehirde amaçsız gezerken"
          ]
        },
        {
          "label": "Evde dinlenirken",
          "neighbors": [
            "Aile ziyaretinde",
            "Hobi projesinde",
            "Spor salonunda",
            "Uykuda"
          ]
        },
        {
          "label": "Kafe turunda",
          "neighbors": [
            "Gece çıkışında",
            "Konserde",
            "Kültürel etkinlikte",
            "Şehirde amaçsız gezerken"
          ]
        },
        {
          "label": "Gece çıkışında",
          "neighbors": [
            "Kafe turunda",
            "Konserde",
            "Kültürel etkinlikte",
            "Şehirde amaçsız gezerken"
          ]
        },
        {
          "label": "Sahada spor yaparken",
          "neighbors": [
            "Doğa yürüyüşünde",
            "Kampta",
            "Spor salonunda",
            "Yolculukta"
          ]
        },
        {
          "label": "Spor salonunda",
          "neighbors": [
            "Doğa yürüyüşünde",
            "Evde dinlenirken",
            "Hobi projesinde",
            "Sahada spor yaparken",
            "Uykuda"
          ]
        },
        {
          "label": "Yolculukta",
          "neighbors": [
            "Aile ziyaretinde",
            "Doğa yürüyüşünde",
            "Kampta",
            "Sahada spor yaparken",
            "Şehirde amaçsız gezerken"
          ]
        },
        {
          "label": "Aile ziyaretinde",
          "neighbors": [
            "Evde dinlenirken",
            "Hobi projesinde",
            "Uykuda",
            "Yolculukta"
          ]
        },
        {
          "label": "Kültürel etkinlikte",
          "neighbors": [
            "Gece çıkışında",
            "Hobi projesinde",
            "Kafe turunda",
            "Konserde",
            "Şehirde amaçsız gezerken"
          ]
        },
        {
          "label": "Konserde",
          "neighbors": [
            "Gece çıkışında",
            "Kafe turunda",
            "Kültürel etkinlikte",
            "Şehirde amaçsız gezerken"
          ]
        },
        {
          "label": "Hobi projesinde",
          "neighbors": [
            "Aile ziyaretinde",
            "Evde dinlenirken",
            "Kültürel etkinlikte",
            "Spor salonunda",
            "Uykuda"
          ]
        },
        {
          "label": "Şehirde amaçsız gezerken",
          "neighbors": [
            "Doğa yürüyüşünde",
            "Gece çıkışında",
            "Kafe turunda",
            "Kampta",
            "Konserde",
            "Kültürel etkinlikte",
            "Yolculukta"
          ]
        },
        {
          "label": "Uykuda",
          "neighbors": [
            "Aile ziyaretinde",
            "Evde dinlenirken",
            "Hobi projesinde",
            "Spor salonunda"
          ]
        }
      ]
    },
    {
      "code": "karakter",
      "question_body": "Sence ben aşağıdakilerden hangisine daha çok uyuyorum?",
      "items": [
        {
          "label": "Meraklı kaşif",
          "neighbors": [
            "Analitik",
            "Spontane",
            "Yaratıcı",
            "Şakacı"
          ]
        },
        {
          "label": "Sakin gözlemci",
          "neighbors": [
            "Analitik",
            "Destekleyici",
            "Planlayıcı",
            "Uyumlu"
          ]
        },
        {
          "label": "Planlayıcı",
          "neighbors": [
            "Analitik",
            "Kararlı",
            "Lider",
            "Rekabetçi",
            "Sakin gözlemci"
          ]
        },
        {
          "label": "Spontane",
          "neighbors": [
            "Lider",
            "Meraklı kaşif",
            "Rekabetçi",
            "Yaratıcı",
            "Şakacı"
          ]
        },
        {
          "label": "Rekabetçi",
          "neighbors": [
            "Kararlı",
            "Lider",
            "Planlayıcı",
            "Spontane"
          ]
        },
        {
          "label": "Destekleyici",
          "neighbors": [
            "Sakin gözlemci",
            "Uyumlu",
            "Yaratıcı",
            "Şakacı"
          ]
        },
        {
          "label": "Yaratıcı",
          "neighbors": [
            "Analitik",
            "Destekleyici",
            "Meraklı kaşif",
            "Spontane",
            "Uyumlu"
          ]
        },
        {
          "label": "Analitik",
          "neighbors": [
            "Kararlı",
            "Meraklı kaşif",
            "Planlayıcı",
            "Sakin gözlemci",
            "Yaratıcı"
          ]
        },
        {
          "label": "Lider",
          "neighbors": [
            "Kararlı",
            "Planlayıcı",
            "Rekabetçi",
            "Spontane"
          ]
        },
        {
          "label": "Uyumlu",
          "neighbors": [
            "Destekleyici",
            "Sakin gözlemci",
            "Yaratıcı",
            "Şakacı"
          ]
        },
        {
          "label": "Kararlı",
          "neighbors": [
            "Analitik",
            "Lider",
            "Planlayıcı",
            "Rekabetçi"
          ]
        },
        {
          "label": "Şakacı",
          "neighbors": [
            "Destekleyici",
            "Meraklı kaşif",
            "Spontane",
            "Uyumlu"
          ]
        }
      ]
    },
    {
      "code": "seyahat",
      "question_body": "Nasıl bir gezginim?",
      "items": [
        {
          "label": "Sırt çantalı",
          "neighbors": [
            "Dağcı",
            "Kampçı",
            "Kültür avcısı",
            "Yalnız gezgin"
          ]
        },
        {
          "label": "Konfor ve lüks",
          "neighbors": [
            "Kültür avcısı",
            "Pek gezmem",
            "Plajcı",
            "Yemek turisti",
            "Şehir gezgini"
          ]
        },
        {
          "label": "Kampçı",
          "neighbors": [
            "Dağcı",
            "Plajcı",
            "Sırt çantalı",
            "Yalnız gezgin"
          ]
        },
        {
          "label": "Şehir gezgini",
          "neighbors": [
            "Dağcı",
            "Konfor ve lüks",
            "Kültür avcısı",
            "Pek gezmem",
            "Plajcı",
            "Yemek turisti"
          ]
        },
        {
          "label": "Plajcı",
          "neighbors": [
            "Kampçı",
            "Konfor ve lüks",
            "Pek gezmem",
            "Yemek turisti",
            "Şehir gezgini"
          ]
        },
        {
          "label": "Dağcı",
          "neighbors": [
            "Kampçı",
            "Sırt çantalı",
            "Yalnız gezgin",
            "Şehir gezgini"
          ]
        },
        {
          "label": "Kültür avcısı",
          "neighbors": [
            "Konfor ve lüks",
            "Sırt çantalı",
            "Yalnız gezgin",
            "Yemek turisti",
            "Şehir gezgini"
          ]
        },
        {
          "label": "Yemek turisti",
          "neighbors": [
            "Konfor ve lüks",
            "Kültür avcısı",
            "Pek gezmem",
            "Plajcı",
            "Şehir gezgini"
          ]
        },
        {
          "label": "Yalnız gezgin",
          "neighbors": [
            "Dağcı",
            "Kampçı",
            "Kültür avcısı",
            "Sırt çantalı"
          ]
        },
        {
          "label": "Pek gezmem",
          "neighbors": [
            "Konfor ve lüks",
            "Plajcı",
            "Yemek turisti",
            "Şehir gezgini"
          ]
        }
      ]
    },
    {
      "code": "film",
      "question_body": "Hangi türü tercih ederim?",
      "items": [
        {
          "label": "Bilim kurgu",
          "neighbors": [
            "Aksiyon",
            "Animasyon",
            "Belgesel",
            "Fantastik",
            "Gerilim"
          ]
        },
        {
          "label": "Fantastik",
          "neighbors": [
            "Aksiyon",
            "Animasyon",
            "Bilim kurgu",
            "Korku",
            "Tarihi"
          ]
        },
        {
          "label": "Gerilim",
          "neighbors": [
            "Aksiyon",
            "Bilim kurgu",
            "Korku",
            "Suç ve polisiye"
          ]
        },
        {
          "label": "Korku",
          "neighbors": [
            "Aksiyon",
            "Fantastik",
            "Gerilim",
            "Suç ve polisiye"
          ]
        },
        {
          "label": "Komedi",
          "neighbors": [
            "Aksiyon",
            "Animasyon",
            "Dram",
            "Romantik"
          ]
        },
        {
          "label": "Dram",
          "neighbors": [
            "Belgesel",
            "Komedi",
            "Romantik",
            "Tarihi"
          ]
        },
        {
          "label": "Belgesel",
          "neighbors": [
            "Bilim kurgu",
            "Dram",
            "Suç ve polisiye",
            "Tarihi"
          ]
        },
        {
          "label": "Animasyon",
          "neighbors": [
            "Bilim kurgu",
            "Fantastik",
            "Komedi",
            "Romantik"
          ]
        },
        {
          "label": "Suç ve polisiye",
          "neighbors": [
            "Aksiyon",
            "Belgesel",
            "Gerilim",
            "Korku"
          ]
        },
        {
          "label": "Romantik",
          "neighbors": [
            "Animasyon",
            "Dram",
            "Komedi",
            "Tarihi"
          ]
        },
        {
          "label": "Aksiyon",
          "neighbors": [
            "Bilim kurgu",
            "Fantastik",
            "Gerilim",
            "Komedi",
            "Korku",
            "Suç ve polisiye"
          ]
        },
        {
          "label": "Tarihi",
          "neighbors": [
            "Belgesel",
            "Dram",
            "Fantastik",
            "Romantik"
          ]
        }
      ]
    },
    {
      "code": "icecek",
      "question_body": "Elimde genelde ne olur?",
      "items": [
        {
          "label": "Türk kahvesi",
          "neighbors": [
            "Bitki çayı",
            "Espresso",
            "Filtre kahve",
            "Çay"
          ]
        },
        {
          "label": "Espresso",
          "neighbors": [
            "Filtre kahve",
            "Latte",
            "Soğuk kahve",
            "Türk kahvesi"
          ]
        },
        {
          "label": "Filtre kahve",
          "neighbors": [
            "Espresso",
            "Latte",
            "Soğuk kahve",
            "Sıcak çikolata",
            "Türk kahvesi"
          ]
        },
        {
          "label": "Latte",
          "neighbors": [
            "Enerji içeceği",
            "Espresso",
            "Filtre kahve",
            "Soğuk kahve",
            "Sıcak çikolata"
          ]
        },
        {
          "label": "Çay",
          "neighbors": [
            "Ayran",
            "Bitki çayı",
            "Sade su",
            "Sıcak çikolata",
            "Türk kahvesi"
          ]
        },
        {
          "label": "Bitki çayı",
          "neighbors": [
            "Sade su",
            "Sıcak çikolata",
            "Türk kahvesi",
            "Çay"
          ]
        },
        {
          "label": "Soğuk kahve",
          "neighbors": [
            "Enerji içeceği",
            "Espresso",
            "Filtre kahve",
            "Gazlı içecek",
            "Latte"
          ]
        },
        {
          "label": "Enerji içeceği",
          "neighbors": [
            "Ayran",
            "Gazlı içecek",
            "Latte",
            "Soğuk kahve"
          ]
        },
        {
          "label": "Ayran",
          "neighbors": [
            "Enerji içeceği",
            "Gazlı içecek",
            "Sade su",
            "Çay"
          ]
        },
        {
          "label": "Gazlı içecek",
          "neighbors": [
            "Ayran",
            "Enerji içeceği",
            "Sade su",
            "Soğuk kahve"
          ]
        },
        {
          "label": "Sıcak çikolata",
          "neighbors": [
            "Bitki çayı",
            "Filtre kahve",
            "Latte",
            "Çay"
          ]
        },
        {
          "label": "Sade su",
          "neighbors": [
            "Ayran",
            "Bitki çayı",
            "Gazlı içecek",
            "Çay"
          ]
        }
      ]
    },
    {
      "code": "yer",
      "question_body": "Nerede yaşamak isterdim?",
      "items": [
        {
          "label": "Metropolün göbeği",
          "neighbors": [
            "Fark etmez, gezerim",
            "Sakin bir mahalle",
            "Yurt dışında bir şehir",
            "Üniversite çevresi"
          ]
        },
        {
          "label": "Sakin bir mahalle",
          "neighbors": [
            "Kasaba",
            "Köy",
            "Metropolün göbeği",
            "Sahil kasabası",
            "Üniversite çevresi"
          ]
        },
        {
          "label": "Sahil kasabası",
          "neighbors": [
            "Ada",
            "Dağ evi",
            "Fark etmez, gezerim",
            "Kasaba",
            "Sakin bir mahalle",
            "Yurt dışında bir şehir"
          ]
        },
        {
          "label": "Dağ evi",
          "neighbors": [
            "Ada",
            "Kasaba",
            "Köy",
            "Sahil kasabası"
          ]
        },
        {
          "label": "Köy",
          "neighbors": [
            "Ada",
            "Dağ evi",
            "Kasaba",
            "Sakin bir mahalle"
          ]
        },
        {
          "label": "Üniversite çevresi",
          "neighbors": [
            "Fark etmez, gezerim",
            "Metropolün göbeği",
            "Sakin bir mahalle",
            "Yurt dışında bir şehir"
          ]
        },
        {
          "label": "Yurt dışında bir şehir",
          "neighbors": [
            "Fark etmez, gezerim",
            "Metropolün göbeği",
            "Sahil kasabası",
            "Üniversite çevresi"
          ]
        },
        {
          "label": "Ada",
          "neighbors": [
            "Dağ evi",
            "Kasaba",
            "Köy",
            "Sahil kasabası"
          ]
        },
        {
          "label": "Kasaba",
          "neighbors": [
            "Ada",
            "Dağ evi",
            "Köy",
            "Sahil kasabası",
            "Sakin bir mahalle"
          ]
        },
        {
          "label": "Fark etmez, gezerim",
          "neighbors": [
            "Metropolün göbeği",
            "Sahil kasabası",
            "Yurt dışında bir şehir",
            "Üniversite çevresi"
          ]
        }
      ]
    }
  ],
  "taxonomy_question_templates": [
    {
      "code": "tax_tarz",
      "category": "tarz",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sence tarzım aşağıdakilerden hangisine daha çok uyuyor?",
      "taxonomy_code": "tarz",
      "options": []
    },
    {
      "code": "tax_muzik",
      "category": "muzik",
      "act": 1,
      "default_difficulty": "medium",
      "body": "En çok hangi türü dinlerim?",
      "taxonomy_code": "muzik",
      "options": []
    },
    {
      "code": "tax_hafta_sonu",
      "category": "hafta_sonu",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Hafta sonu beni en çok nerede bulursun?",
      "taxonomy_code": "hafta_sonu",
      "options": []
    },
    {
      "code": "tax_karakter",
      "category": "karakter",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Sence ben aşağıdakilerden hangisine daha çok uyuyorum?",
      "taxonomy_code": "karakter",
      "options": []
    },
    {
      "code": "tax_seyahat",
      "category": "seyahat",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Nasıl bir gezginim?",
      "taxonomy_code": "seyahat",
      "options": []
    },
    {
      "code": "tax_film",
      "category": "film",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Hangi türü tercih ederim?",
      "taxonomy_code": "film",
      "options": []
    },
    {
      "code": "tax_icecek",
      "category": "icecek",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Elimde genelde ne olur?",
      "taxonomy_code": "icecek",
      "options": []
    },
    {
      "code": "tax_yer",
      "category": "yer",
      "act": 1,
      "default_difficulty": "medium",
      "body": "Nerede yaşamak isterdim?",
      "taxonomy_code": "yer",
      "options": []
    }
  ]
}$farket_seed$::jsonb as data;

-- =========================================================================
-- 1) taxonomies
-- =========================================================================
insert into public.taxonomies (code, question_body, name)
select x.code, x.question_body, x.code
from jsonb_to_recordset((select data from _seed_json) -> 'taxonomies')
  as x(code text, question_body text)
on conflict (code) where code is not null do update set
  question_body = excluded.question_body;

-- =========================================================================
-- 2) taxonomy_items -- her taksonominin items[] dizisindeki label'lar.
-- =========================================================================
insert into public.taxonomy_items (taxonomy_id, label)
select t.id, item.value ->> 'label'
from jsonb_array_elements((select data from _seed_json) -> 'taxonomies') as tx(value)
join public.taxonomies t on t.code = tx.value ->> 'code'
cross join lateral jsonb_array_elements(tx.value -> 'items') as item(value)
on conflict (taxonomy_id, label) do nothing;

-- =========================================================================
-- 3) taxonomy_adjacency -- items[].neighbors[] zaten simetrik kaydedilmis
-- (kaynak dosyada A->B varsa B->A da var), o yuzden tek gecis yeterli.
-- =========================================================================
insert into public.taxonomy_adjacency (item_id, neighbor_item_id)
select ti.id, tn.id
from jsonb_array_elements((select data from _seed_json) -> 'taxonomies') as tx(value)
join public.taxonomies t on t.code = tx.value ->> 'code'
cross join lateral jsonb_array_elements(tx.value -> 'items') as item(value)
join public.taxonomy_items ti on ti.taxonomy_id = t.id and ti.label = item.value ->> 'label'
cross join lateral jsonb_array_elements_text(item.value -> 'neighbors') as nb(value)
join public.taxonomy_items tn on tn.taxonomy_id = t.id and tn.label = nb.value
on conflict (item_id, neighbor_item_id) do nothing;

-- =========================================================================
-- 4) question_templates -- 140 sabit sikli kalip.
-- =========================================================================
insert into public.question_templates (code, category, act, default_difficulty, body)
select x.code, x.category, x.act, x.default_difficulty, x.body
from jsonb_to_recordset((select data from _seed_json) -> 'question_templates')
  as x(code text, category text, act int, default_difficulty text, body text)
on conflict (code) where code is not null do update set
  category = excluded.category,
  act = excluded.act,
  default_difficulty = excluded.default_difficulty,
  body = excluded.body;

-- =========================================================================
-- 5) template_options -- (template_id, position) uzerinden idempotent.
-- =========================================================================
insert into public.template_options (template_id, body, position)
select qt.id, opt.value, opt.ordinality
from jsonb_array_elements((select data from _seed_json) -> 'question_templates') as q(value)
join public.question_templates qt on qt.code = q.value ->> 'code'
cross join lateral jsonb_array_elements_text(q.value -> 'options') with ordinality as opt(value, ordinality)
on conflict (template_id, position) do update set
  body = excluded.body;

-- =========================================================================
-- 6) taxonomy_question_templates -- 8 taksonomi sorusu, taxonomy_id dolu,
-- template_options YOK (options[] zaten bos dizi, lateral join otomatik
-- sifir satir uretir).
-- =========================================================================
insert into public.question_templates (code, category, act, default_difficulty, body, taxonomy_id)
select x.code, x.category, x.act, x.default_difficulty, x.body, t.id
from jsonb_to_recordset((select data from _seed_json) -> 'taxonomy_question_templates')
  as x(code text, category text, act int, default_difficulty text, body text, taxonomy_code text)
join public.taxonomies t on t.code = x.taxonomy_code
on conflict (code) where code is not null do update set
  category = excluded.category,
  act = excluded.act,
  default_difficulty = excluded.default_difficulty,
  body = excluded.body,
  taxonomy_id = excluded.taxonomy_id;
