package com.farket.app.ui.theme

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.sin

/**
 * Gündüz/gece anahtarı — güneş ve ay arasında geçen tek bir animasyonlu ikon.
 *
 * Ayrı bir "ay" çizimi yok: aynı daire, sağ üstten kayarak gelen ikinci bir daireyle
 * hilale dönüşüyor. Kesme dairesi zemin rengiyle çiziliyor (katman/BlendMode gerekmiyor,
 * düğmenin arkası zaten düz renk). Işınlar aynı anda kısalıp saydamlaşıyor ve tüm çizim
 * hafifçe dönüyor — geçiş "iki ikon arasında geçiş" gibi değil, tek nesnenin dönüşümü
 * gibi okunuyor.
 */
@Composable
fun ThemeModeToggle(
    isDark: Boolean,
    onToggle: (nextIsDark: Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalFarketColors.current
    val shape = RoundedCornerShape(14.dp)

    val progress by animateFloatAsState(
        targetValue = if (isDark) 1f else 0f,
        animationSpec = tween(durationMillis = 500, easing = FastOutSlowInEasing),
        label = "themeMorph",
    )

    Box(
        modifier = modifier
            .size(46.dp)
            .shadow(
                elevation = 12.dp,
                shape = shape,
                ambientColor = colors.accent.copy(alpha = 0.55f),
                spotColor = Color.Black,
            )
            .shadow(elevation = 3.dp, shape = shape, ambientColor = Color.Black, spotColor = Color.Black)
            .clip(shape)
            .background(colors.surface)
            .border(1.dp, colors.line, shape)
            .clickable { onToggle(!isDark) }
            .semantics {
                contentDescription = if (isDark) "Gece modu açık, gündüz moduna geç" else "Gündüz modu açık, gece moduna geç"
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.size(24.dp)) {
            val glyph = size.minDimension
            val center = Offset(size.width / 2f, size.height / 2f)
            val tint = colors.accent

            // Güneşken daha küçük (ışınlara yer kalsın), ayken daha dolgun.
            val bodyRadius = glyph * (0.30f + 0.10f * progress)

            rotate(degrees = -55f * progress, pivot = center) {
                // Işınlar: yalnızca güneş tarafında görünür.
                val rayAlpha = (1f - progress * 1.6f).coerceIn(0f, 1f)
                if (rayAlpha > 0f) {
                    val inner = bodyRadius + glyph * 0.10f
                    val outer = inner + glyph * 0.16f * (1f - progress)
                    repeat(8) { i ->
                        val angle = (Math.PI / 4.0) * i
                        val dx = cos(angle).toFloat()
                        val dy = sin(angle).toFloat()
                        drawLine(
                            color = tint.copy(alpha = rayAlpha),
                            start = Offset(center.x + dx * inner, center.y + dy * inner),
                            end = Offset(center.x + dx * outer, center.y + dy * outer),
                            strokeWidth = glyph * 0.075f,
                        )
                    }
                }

                drawCircle(color = tint, radius = bodyRadius, center = center)

                // Hilali oyan daire: progress 0'da tuvalin dışında, 1'de gövdenin
                // sağ üstüne oturur.
                if (progress > 0f) {
                    val travel = 1.35f - 0.90f * progress
                    drawCircle(
                        color = colors.surface,
                        radius = bodyRadius * 0.92f,
                        center = Offset(
                            x = center.x + glyph * travel,
                            y = center.y - glyph * travel * 0.75f,
                        ),
                    )
                }
            }
        }
    }
}
