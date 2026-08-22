package com.farket.app.ui.onboarding

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.farket.app.ui.theme.LocalFarketColors
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private data class OnboardingItem(val title: String, val body: String)

private val ONBOARDING_ITEMS = listOf(
    OnboardingItem(
        "Fotoğraflar + sorular",
        "Keşfettiğin kişinin fotoğrafları ve kişisel sorularıyla bir quiz çözersin.",
    ),
    OnboardingItem(
        "Hak ettiğini kazan",
        "Yeterince doğru cevap verirsen künyesi (kimlik bilgileri) açılır.",
    ),
    OnboardingItem(
        "Sonra mesajlaş",
        "Künye açıldıktan sonra o kişiyle mesajlaşma hakkı kazanırsın.",
    ),
)

@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    // Girişte iki sayfa: tanıtım, ardından jest provası. Keşif kartındaki "Atla"/
    // "Quizle" düğmeleri kaldırıldığı için kartın nasıl kullanılacağını kullanıcının
    // burada öğrenmesi gerekiyor — okuyup geçmesi değil, bir kez fiilen yapması.
    var showGestureTutorial by remember { mutableStateOf(false) }

    if (showGestureTutorial) {
        SwipeTutorial(onDone = onFinished)
    } else {
        OnboardingIntro(
            onNext = { showGestureTutorial = true },
            onAlreadyHaveAccount = onFinished,
        )
    }
}

@Composable
private fun OnboardingIntro(onNext: () -> Unit, onAlreadyHaveAccount: () -> Unit) {
    val colors = LocalFarketColors.current

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Farket'e hoş geldin", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Profilleri görmeden önce hak etmen gerekir.",
            style = MaterialTheme.typography.bodyLarge,
            color = colors.textSoft,
            modifier = Modifier.padding(top = 8.dp, bottom = 32.dp),
        )

        ONBOARDING_ITEMS.forEachIndexed { index, item ->
            Row(modifier = Modifier.fillMaxWidth().padding(bottom = 20.dp)) {
                Text(
                    "${index + 1}",
                    style = MaterialTheme.typography.titleMedium,
                    color = colors.accent,
                    modifier = Modifier.padding(end = 16.dp),
                )
                Column {
                    Text(item.title, style = MaterialTheme.typography.titleMedium)
                    Text(
                        item.body,
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.textSoft,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
            }
        }

        Button(
            onClick = onNext,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        ) {
            Text("Başla")
        }

        // Girişte ayrı bir "kayıt" akışı yok: LoginScreen e-posta bağlantısıyla hem
        // yeni hem mevcut kullanıcıyı aynı şekilde içeri alıyor, bu yüzden bu buton da
        // aynı onFinished()'ı tetikliyor — yalnızca mevcut kullanıcıya net bir işaret.
        TextButton(
            onClick = onAlreadyHaveAccount,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Zaten hesabın var mı? Giriş yap", color = colors.textSoft)
        }
    }
}

// Prova kartında jestin sayılması için gereken sürükleme mesafesi. Keşif ekranındaki
// eşikten (140.dp) kasten daha küçük: burada amaç ölçmek değil, öğretmek.
private val TUTORIAL_THRESHOLD_DP = 80.dp

/**
 * Jest provası.
 *
 * Kullanıcı devam edebilmek için hem yukarı hem aşağı kaydırmayı bir kez fiilen
 * yapmak zorunda — "okudum geçtim" ile gerçekten anlamak arasındaki farkı kapatmak
 * için. Keşif kartındaki düğmeler kaldırıldığından bu jestler tek giriş yolu.
 */
@Composable
private fun SwipeTutorial(onDone: () -> Unit) {
    val colors = LocalFarketColors.current
    val density = LocalDensity.current
    val thresholdPx = with(density) { TUTORIAL_THRESHOLD_DP.toPx() }
    val scope = rememberCoroutineScope()

    val offsetY = remember { Animatable(0f) }
    var upDone by remember { mutableStateOf(false) }
    var downDone by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Kartları nasıl kullanacaksın?", style = MaterialTheme.typography.headlineSmall)
        Text(
            "Keşfet ekranında her profil tam ekran bir kart. Aşağıdaki kartla bir kez " +
                "dene — ikisini de yapınca devam edebilirsin.",
            style = MaterialTheme.typography.bodyMedium,
            color = colors.textSoft,
            modifier = Modifier.padding(top = 8.dp, bottom = 20.dp),
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(260.dp)
                .offset { IntOffset(0, offsetY.value.roundToInt()) }
                .background(colors.surface, RoundedCornerShape(20.dp))
                .border(1.dp, colors.accent, RoundedCornerShape(20.dp))
                .pointerInput(Unit) {
                    detectVerticalDragGestures(
                        onVerticalDrag = { change, dragAmount ->
                            change.consume()
                            scope.launch { offsetY.snapTo(offsetY.value + dragAmount) }
                        },
                        onDragEnd = {
                            if (offsetY.value <= -thresholdPx) upDone = true
                            if (offsetY.value >= thresholdPx) downDone = true
                            scope.launch { offsetY.animateTo(0f) }
                        },
                    )
                },
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("↑", style = MaterialTheme.typography.headlineMedium, color = colors.accent)
                Text(
                    "Yukarı kaydır — quizi çöz",
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (upDone) colors.correct else colors.text,
                )
                Text(
                    if (upDone) "yaptın ✓" else "hâlâ bekliyor",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (upDone) colors.correct else colors.textFaint,
                    modifier = Modifier.padding(bottom = 24.dp),
                )
                Text(
                    "Aşağı kaydır — bu profili atla",
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (downDone) colors.correct else colors.text,
                )
                Text(
                    if (downDone) "yaptın ✓" else "hâlâ bekliyor",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (downDone) colors.correct else colors.textFaint,
                )
                Text("↓", style = MaterialTheme.typography.headlineMedium, color = colors.accent)
            }
        }

        Text(
            "Karta ortadan dokunursan profili açarsın; sağ ve sol kenarlara dokunmak " +
                "fotoğraflar arasında gezdirir.",
            style = MaterialTheme.typography.bodySmall,
            color = colors.textSoft,
            modifier = Modifier.padding(top = 20.dp),
        )

        val ready = upDone && downDone
        if (!ready) {
            Text(
                text = when {
                    !upDone && !downDone -> "Devam etmek için kartı bir kez yukarı, bir kez aşağı kaydır."
                    !upDone -> "Bir de yukarı kaydırmayı dene."
                    else -> "Bir de aşağı kaydırmayı dene."
                },
                style = MaterialTheme.typography.bodySmall,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 16.dp),
            )
        }

        Button(
            onClick = onDone,
            enabled = ready,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        ) {
            Text("Anladım, devam et")
        }
    }
}
