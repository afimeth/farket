package com.farket.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Farket'in tasarım tokenları — design-canvas/farket-canvas.html'deki interaktif
 * prototipten (Giriş/Keşfet/Quiz/Mesajlar artboard'ları) birebir alındı. Üç renk
 * yönü var (Oda / Fener / Alaca), her biri dark+light varyantlı; uygulama şimdilik
 * yalnızca "Oda" (varsayılan, prototipteki ekran görüntülerinde görünen) paleti kullanıyor.
 */
enum class FarketPaletteName { ODA, FENER, ALACA }

data class FarketColors(
    val bg: Color,
    val surface: Color,
    val veil: Color,
    val veil2: Color,
    val text: Color,
    val textSoft: Color,
    val textFaint: Color,
    val accent: Color,
    val accentInk: Color,
    val line: Color,
    val correct: Color,
)

object FarketPalettes {
    val odaDark = FarketColors(
        bg = Color(0xFF170C10),
        surface = Color(0xFF221319),
        veil = Color(0xFF3C2536),
        veil2 = Color(0xFF4D2F45),
        text = Color(0xFFF3ECE1),
        textSoft = Color(0xFFB7A69C),
        textFaint = Color(0xFF8B7B77),
        accent = Color(0xFFE0902F),
        accentInk = Color(0xFF170C10),
        line = Color(0x1AF3ECE1),
        correct = Color(0xFF8FAE84),
    )

    // Gündüz modu beyaz tonlarında: zemin kırık beyaz, yüzeyler saf beyaz.
    // İkisinin AYNI olmaması önemli — kart, menü ikonu gibi "surface" kullanan
    // öğelerin zeminden ayrışması buna dayanıyor (koyu modda da aynı ilişki var,
    // yalnızca yön ters: orada yüzey zeminden açık, burada da açık).
    // Metin ve vurgu renkleri koyu varyantın tonunu koruyor, yalnızca beyaz üstünde
    // okunacak kadar koyulaştırıldı — iki mod aynı ailede kalsın diye.
    // Ürün kararı: gündüz modunda yazılar da karanlık modun vurgu renginin ailesinde
    // (amber) olsun — ama okunur kalsın. Bu yüzden vurgunun kendisi değil, KOYU
    // TONLARI kullanılıyor: doğrudan #E0902F beyaz zeminde ~2,4:1 kontrast veriyor,
    // WCAG AA gövde metni için 4,5:1 gerekiyor.
    //   text      ~8,1:1  (gövde metni)
    //   textSoft  ~5,3:1  (ikincil metin)
    //   textFaint ~3,3:1  (yalnızca ipucu/etiket, gövde metni için kullanılmaz)
    // accent daha parlak kalıyor ki dolgu/vurgu olarak metinden ayrışsın.
    val odaLight = FarketColors(
        bg = Color(0xFFF6F2EE),
        surface = Color(0xFFFFFFFF),
        veil = Color(0xFF3C2536),
        veil2 = Color(0xFF4D2F45),
        text = Color(0xFF6B3F0A),
        textSoft = Color(0xFF8C5A16),
        textFaint = Color(0xFFA97F42),
        accent = Color(0xFFC2761B),
        accentInk = Color(0xFFFFFFFF),
        line = Color(0x2E6B3F0A),
        correct = Color(0xFF4F7355),
    )

    val fenerDark = FarketColors(
        bg = Color(0xFF111113),
        surface = Color(0xFF1C1C1F),
        veil = Color(0xFF2A2A2E),
        veil2 = Color(0xFF38383D),
        text = Color(0xFFF7F5F1),
        textSoft = Color(0xFFB4B0AA),
        textFaint = Color(0xFF807C77),
        accent = Color(0xFFE7A53D),
        accentInk = Color(0xFF17140F),
        line = Color(0x17F7F5F1),
        correct = Color(0xFF8FB37E),
    )

    val fenerLight = FarketColors(
        bg = Color(0xFFF4F4F2),
        surface = Color(0xFFFFFFFF),
        veil = Color(0xFF2A2A2E),
        veil2 = Color(0xFF38383D),
        // Fener'in altın vurgusunun (#E7A53D) koyu tonları.
        text = Color(0xFF6B4E08),
        textSoft = Color(0xFF8A6714),
        textFaint = Color(0xFFA98A45),
        accent = Color(0xFFA8760F),
        accentInk = Color(0xFFFFFFFF),
        line = Color(0x2E6B4E08),
        correct = Color(0xFF4F7A45),
    )

    val alacaDark = FarketColors(
        bg = Color(0xFF12121F),
        surface = Color(0xFF1C1C30),
        veil = Color(0xFF312A52),
        veil2 = Color(0xFF3E3468),
        text = Color(0xFFEFEAF7),
        textSoft = Color(0xFFADA6C4),
        textFaint = Color(0xFF7A7396),
        accent = Color(0xFFE8735A),
        accentInk = Color(0xFF17111C),
        line = Color(0x1AEFEAF7),
        correct = Color(0xFF6FAE9C),
    )

    val alacaLight = FarketColors(
        bg = Color(0xFFF3F2F8),
        surface = Color(0xFFFFFFFF),
        veil = Color(0xFF312A52),
        veil2 = Color(0xFF3E3468),
        // Alaca'nın mercan vurgusunun (#E8735A) koyu tonları.
        text = Color(0xFF7A2E1C),
        textSoft = Color(0xFF9B4531),
        textFaint = Color(0xFFB57160),
        accent = Color(0xFFC9513A),
        accentInk = Color(0xFFFFFFFF),
        line = Color(0x2E7A2E1C),
        correct = Color(0xFF3A8877),
    )

    fun of(name: FarketPaletteName, dark: Boolean): FarketColors = when (name) {
        FarketPaletteName.ODA -> if (dark) odaDark else odaLight
        FarketPaletteName.FENER -> if (dark) fenerDark else fenerLight
        FarketPaletteName.ALACA -> if (dark) alacaDark else alacaLight
    }
}
