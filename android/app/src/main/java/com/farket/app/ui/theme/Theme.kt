package com.farket.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * `FarketColors` — design-canvas/farket-canvas.html prototipindeki tam token
 * setini (bg/surface/veil/text/accent/line/…) taşır. Material3'ün ColorScheme'i
 * (primary/surface/…) yalnızca sistem bileşenleri (TextField/Button varsayılanları)
 * için köprü olarak dolduruluyor — ekranlar kendi görselliğini LocalFarketColors'tan
 * okuyup prototipteki tasarımı birebir uygular.
 */
val LocalFarketColors = staticCompositionLocalOf { FarketPalettes.odaDark }
val LocalFarketPalette = compositionLocalOf { FarketPaletteName.ODA }

@Composable
fun FarketTheme(
    palette: FarketPaletteName = FarketPaletteName.ODA,
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = FarketPalettes.of(palette, darkTheme)
    val materialScheme = if (darkTheme) {
        darkColorScheme(
            primary = colors.accent,
            onPrimary = colors.accentInk,
            background = colors.bg,
            onBackground = colors.text,
            surface = colors.surface,
            onSurface = colors.text,
            surfaceVariant = colors.veil,
            outline = colors.line,
        )
    } else {
        lightColorScheme(
            primary = colors.accent,
            onPrimary = colors.accentInk,
            background = colors.bg,
            onBackground = colors.text,
            surface = colors.surface,
            onSurface = colors.text,
            surfaceVariant = colors.veil,
            outline = colors.line,
        )
    }

    CompositionLocalProvider(
        LocalFarketColors provides colors,
        LocalFarketPalette provides palette,
    ) {
        MaterialTheme(
            colorScheme = materialScheme,
            typography = farketTypography(colors),
            content = content,
        )
    }
}
