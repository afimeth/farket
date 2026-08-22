package com.farket.app.ui.quiz

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.R
import com.farket.app.data.identity.IDENTITY_ATTRIBUTE_LABELS
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.theme.LocalFarketColors

/**
 * Quiz akışı — bkz. proje notları FARKET_PROMPTLAR.md Prompt 5. Sorular sırayla cevaplanır,
 * 5. sorudan sonra checkpoint ara ekranı, 10. sorudan sonra sonuç ekranı gösterilir.
 */
@Composable
fun QuizScreen(
    onEliminated: () -> Unit,
    onOpenIdentity: (attemptId: String) -> Unit,
    onOpenMessage: (targetProfileId: String, unlockedTier: Int) -> Unit,
    viewModel: QuizViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()

    // 2. Bölüm (pozisyon 6-10) profil sahibinin künye/serbest sorularını içerir —
    // bu blok tamamlanmadan sistem geri tuşu/kaydırma jesti ile çıkılamaz. Hero
    // card da bu geçişin bir parçası olduğu için aynı şekilde korunuyor.
    val isExitGuarded = when (val state = uiState) {
        is QuizUiState.Question -> isExitGuardedPosition(state.position)
        is QuizUiState.HeroCard -> true
        else -> false
    }
    BackHandler(enabled = isExitGuarded) { /* no-op: bu bölümde geri çıkış yok */ }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        when (val state = uiState) {
            is QuizUiState.Loading -> {
                CircularProgressIndicator()
            }
            is QuizUiState.Error -> {
                Text(state.message, color = MaterialTheme.colorScheme.error)
            }
            is QuizUiState.Question -> {
                QuestionContent(state, onAnswer = viewModel::answer)
            }
            is QuizUiState.CheckpointResult -> {
                CheckpointContent(
                    state = state,
                    onContinue = viewModel::continueAfterCheckpoint,
                    onGoToDiscovery = onEliminated,
                )
            }
            is QuizUiState.HeroCard -> {
                HeroCardContent(state = state, onContinue = viewModel::continueAfterCheckpoint)
            }
            is QuizUiState.Finished -> {
                FinishedContent(state = state, onOpenIdentity = onOpenIdentity, onOpenMessage = onOpenMessage)
            }
        }
    }
}

@Composable
private fun QuestionContent(state: QuizUiState.Question, onAnswer: (String) -> Unit) {
    val colors = LocalFarketColors.current

    LinearProgressIndicator(
        progress = { state.position / 10f },
        color = colors.accent,
        trackColor = colors.veil,
        modifier = Modifier.fillMaxWidth(),
    )
    Text(
        "${state.position} / 10 · SKOR ${state.score}",
        style = MaterialTheme.typography.labelMedium,
        modifier = Modifier.padding(top = 8.dp, bottom = 20.dp),
    )
    Text(state.question.questionBody, style = MaterialTheme.typography.titleLarge)

    Column(modifier = Modifier.padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        state.question.options.forEach { option ->
            OutlinedButton(
                onClick = { onAnswer(option.id) },
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, colors.line),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.text),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(option.body, modifier = Modifier.padding(vertical = 6.dp))
            }
        }
    }
}

@Composable
private fun CheckpointContent(
    state: QuizUiState.CheckpointResult,
    onContinue: () -> Unit,
    onGoToDiscovery: () -> Unit,
) {
    val colors = LocalFarketColors.current

    // checkpointPassed=true artık doğrudan HeroCard state'ine geçiyor (bkz.
    // QuizViewModel.answer) — bu ekran yalnızca başarısız checkpoint için kalır.
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(
            painter = painterResource(R.drawable.ic_launcher_foreground),
            contentDescription = null,
            modifier = Modifier.size(72.dp),
        )
        Text(
            "Bu sefer olmadı.",
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(top = 12.dp),
        )

        // Soru soru skor dökümü: ilk `score` kutu doğru (correct), kalanı boş (veil).
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.padding(top = 16.dp),
        ) {
            repeat(5) { index ->
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(if (index < state.score) colors.correct else colors.veil),
                )
            }
        }
        Text(
            "5 sorudan ${state.score} doğru — bu profil önümüzdeki 3 gün sana kapalı.",
            style = MaterialTheme.typography.bodyMedium,
            color = colors.textSoft,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 12.dp, start = 32.dp, end = 32.dp),
        )
        Text(
            "Süre dolunca profil desteye geri döner. Ayarlar'daki \"Beklemedeki profiller\" bölümünden haftada bir kez erken açabilirsin.",
            style = MaterialTheme.typography.bodySmall,
            color = colors.textFaint,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp, bottom = 24.dp, start = 32.dp, end = 32.dp),
        )
        Button(
            onClick = onGoToDiscovery,
            shape = RoundedCornerShape(20.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = colors.accent,
                contentColor = colors.accentInk,
            ),
        ) { Text("Keşfe Dön", modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp)) }
    }
}

@Composable
private fun HeroCardContent(
    state: QuizUiState.HeroCard,
    onContinue: () -> Unit,
) {
    val colors = LocalFarketColors.current

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("Tebrikler, sonraki aşamaya geçtin!", style = MaterialTheme.typography.headlineSmall)
        Text(
            "${state.score}/5",
            style = MaterialTheme.typography.headlineSmall,
            color = colors.accent,
            modifier = Modifier.padding(top = 8.dp, bottom = 24.dp),
        )

        if (state.identity.isNotEmpty()) {
            Column(modifier = Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
                state.identity.forEach { (attributeType, value) ->
                    Text(
                        "${IDENTITY_ATTRIBUTE_LABELS[attributeType] ?: attributeType}: $value",
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.padding(vertical = 4.dp),
                    )
                }
            }
        }

        Text(
            "Kalan 5 soruda 1. bölümdeki gibi çıkış yapılamaz — bitirmen gerekiyor.",
            style = MaterialTheme.typography.bodySmall,
            color = colors.textSoft,
            modifier = Modifier.padding(bottom = 24.dp),
        )

        Button(
            onClick = onContinue,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
        ) { Text("2. Bölüme Geç") }
    }
}

@Composable
private fun FinishedContent(
    state: QuizUiState.Finished,
    onOpenIdentity: (attemptId: String) -> Unit,
    onOpenMessage: (targetProfileId: String, unlockedTier: Int) -> Unit,
) {
    val colors = LocalFarketColors.current

    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val tierText = when {
            state.unlockedTier >= 8 -> "Onu iyi okudun."
            state.unlockedTier == 7 -> "Tam kıvamında."
            else -> "Bu sefer yeterli olmadı."
        }
        Text(tierText, style = MaterialTheme.typography.titleMedium)
        Text(
            "Kademe ${state.unlockedTier}",
            style = MaterialTheme.typography.bodyLarge,
            color = colors.textSoft,
            modifier = Modifier.padding(top = 8.dp, bottom = 24.dp),
        )

        if (state.unlockedTier > 0) {
            Button(
                onClick = { onOpenIdentity(state.attemptId) },
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Künyeyi Aç")
            }
            OutlinedButton(
                onClick = { onOpenMessage(state.targetProfileId, state.unlockedTier) },
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, colors.line),
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            ) {
                Text("Mesaj Gönder")
            }
        } else {
            Text(
                "Künyeyi açmak için en az 7 doğru cevap gerekiyor.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}
