package com.farket.app.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.farket.app.R

/**
 * Başlıklar — prototipteki `font-family:'Fraunces',serif`. TTF'ler yerel olarak
 * res/font'a bundle edildi — indirilebilir font sağlayıcısı (Google Fonts/Play
 * Services) gerçek imza sertifikaları olmadan güvenilir kurulamayacağı için
 * tercih edilmedi.
 *
 * Not: ilk bundle edilen dosyalar design_assets'teki woff2'lerden (fontTools ile)
 * dönüştürülmüştü ve yalnızca temel Latin altkümesini içeriyordu — Türkçe'ye özgü
 * İ/Ğ/Ş (U+0130/011E/015E) glifleri eksikti, bu yüzden "Şehir" gibi etiketler ve
 * "İstanbul" gibi şehir adları sessizce yanlış render oluyordu. Dosyalar
 * fonts.gstatic.com'dan tam Latin Extended kapsamı içeren sürümleriyle
 * değiştirildi (bkz. Archivo/Plex Mono altındaki not).
 */
val FraunicesFamily = FontFamily(
    Font(R.font.fraunces_600, FontWeight.SemiBold),
    Font(R.font.fraunces_700, FontWeight.Bold),
)

/** Gövde metni — prototipteki `font-family:'Archivo'`. */
val ArchivoFamily = FontFamily(
    Font(R.font.archivo_regular, FontWeight.Normal),
    Font(R.font.archivo_400, FontWeight.Normal),
    Font(R.font.archivo_500, FontWeight.Medium),
    Font(R.font.archivo_600, FontWeight.SemiBold),
    Font(R.font.archivo_700, FontWeight.Bold),
)

/** Etiketler/mono metin — prototipteki `font-family:'IBM Plex Mono'`. */
val PlexMonoFamily = FontFamily(
    Font(R.font.plex_mono_400, FontWeight.Normal),
    Font(R.font.plex_mono_500, FontWeight.Medium),
)

fun farketTypography(colors: FarketColors) = Typography(
    headlineLarge = TextStyle(
        fontFamily = FraunicesFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 42.sp,
        color = colors.text,
    ),
    headlineMedium = TextStyle(
        fontFamily = FraunicesFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 32.sp,
        color = colors.text,
    ),
    headlineSmall = TextStyle(
        fontFamily = FraunicesFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 34.sp,
        color = colors.text,
    ),
    titleLarge = TextStyle(
        fontFamily = FraunicesFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 23.sp,
        color = colors.text,
    ),
    titleMedium = TextStyle(
        fontFamily = FraunicesFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 21.sp,
        lineHeight = 26.sp,
        color = colors.text,
    ),
    bodyLarge = TextStyle(
        fontFamily = ArchivoFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        color = colors.text,
    ),
    bodyMedium = TextStyle(
        fontFamily = ArchivoFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        color = colors.textSoft,
    ),
    bodySmall = TextStyle(
        fontFamily = ArchivoFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        color = colors.textSoft,
    ),
    labelLarge = TextStyle(
        fontFamily = ArchivoFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 14.sp,
        // Rengi kasıtlı olarak sabitlenmiyor: bu stil Button/OutlinedButton/TextButton'ın
        // varsayılan metin stili olduğu için sabit bir renk (örn. accentInk) tüm buton
        // tiplerine sızar ve outline/text buton metnini arka planla aynı renk yapıp
        // görünmez kılar. Her buton kendi ButtonColors'ıyla içerik rengini belirler.
    ),
    labelMedium = TextStyle(
        fontFamily = PlexMonoFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        letterSpacing = 1.sp,
        color = colors.textFaint,
    ),
    labelSmall = TextStyle(
        fontFamily = PlexMonoFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 11.sp,
        letterSpacing = 0.9.sp,
        color = colors.textFaint,
    ),
)
