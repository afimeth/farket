package com.farket.app.ui.discovery

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.theme.LocalFarketColors

/**
 * Profil detay ekranı — Keşfet kartına ortadan dokununca açılır.
 *
 * Kartın kendisi zaten fotoğrafları ve kullanıcı adını gösterip yukarı kaydırmayla
 * quizi başlatıyor, bu yüzden burası onun tekrarı olmamalı. Bu ekranın işi, kartın
 * yapamadığı iki şey: (1) quiz kredisini harcamadan önce karar vermeye yarayan bilgiyi
 * açıkça sunmak (çözülme oranı, fotoğraf sayısı, şehir), (2) şikayet/engelleme —
 * uygulamadaki tek güvenlik çıkışı burası, bu yüzden ekran kaldırılmadı.
 */
@Composable
fun ProfileDetailScreen(
    onQuiz: (profileId: String) -> Unit,
    viewModel: ProfileDetailViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    var showReportDialog by remember { mutableStateOf(false) }
    var reportReason by remember { mutableStateOf("") }
    var showQuizConfirm by remember { mutableStateOf(false) }

    if (showReportDialog) {
        AlertDialog(
            onDismissRequest = { showReportDialog = false },
            title = { Text("Profili şikayet et") },
            text = {
                OutlinedTextField(
                    value = reportReason,
                    onValueChange = { reportReason = it },
                    label = { Text("Sebep") },
                )
            },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.report(reportReason); showReportDialog = false; reportReason = "" },
                    enabled = reportReason.isNotBlank(),
                ) { Text("Gönder") }
            },
            dismissButton = { TextButton(onClick = { showReportDialog = false }) { Text("Vazgeç") } },
        )
    }

    val colors = LocalFarketColors.current

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        if (uiState.reportSent) {
            Text("Şikayetin gönderildi.", color = colors.correct, modifier = Modifier.padding(bottom = 8.dp))
        }
        if (uiState.blocked) {
            Text("Bu kullanıcıyı engelledin.", color = colors.correct, modifier = Modifier.padding(bottom = 8.dp))
        }
        if (uiState.errorMessage != null) {
            Text(uiState.errorMessage!!, color = MaterialTheme.colorScheme.error)
            return@Column
        }

        if (uiState.isLoading || uiState.profile == null) {
            CircularProgressIndicator(color = colors.accent)
            return@Column
        }

        val profile = uiState.profile!!

        if (showQuizConfirm) {
            // Kartla aynı bilgilendirme: quize iki ayrı giriş noktası var ve ikisinin de
            // maliyeti taahhütten önce söylemesi gerekiyor. Eskiden buradaki düğme
            // doğrudan quizi başlatıyordu, yani şeffaflık yalnızca bir yolda vardı.
            AlertDialog(
                onDismissRequest = { showQuizConfirm = false },
                title = { Text("Quiz'e başla") },
                text = {
                    Text(
                        "@${profile.username} için 10 soruluk quiz başlayacak.\n\n" +
                            "• 5. soruda ara kontrol var: en az 4 doğru gerekiyor.\n" +
                            "• Geçemezsen bu profil 3 gün gizlenir.\n" +
                            "• 7 doğru mesaj hakkı açar; 8'de fotoğrafına değinebilir, " +
                            "9'da gizli kartı görür ve soru sorabilir, 10'da mühür kazanırsın.\n" +
                            "• Bu profil için toplam 2 deneme hakkın var.\n" +
                            "• Günlük quiz hakkından 1 düşer.",
                    )
                },
                confirmButton = {
                    TextButton(onClick = { showQuizConfirm = false; onQuiz(profile.id) }) { Text("Başla") }
                },
                dismissButton = { TextButton(onClick = { showQuizConfirm = false }) { Text("Vazgeç") } },
            )
        }

        Text("@${profile.username}", style = MaterialTheme.typography.headlineSmall)

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth().height(280.dp).padding(top = 12.dp),
        ) {
            items(profile.photos, key = { it.id }) { photo ->
                val url = uiState.photoUrls[photo.id]
                if (url != null) {
                    AsyncImage(
                        model = url,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.height(280.dp).width(190.dp).clip(RoundedCornerShape(16.dp)),
                    )
                } else {
                    CircularProgressIndicator(color = colors.accent)
                }
            }
        }

        // Karar bilgisi: kredi harcamadan önce "bu quiz bana göre mi" sorusuna cevap.
        Text(
            "Quize başlamadan önce",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 20.dp, bottom = 8.dp),
        )
        if (profile.city != null) {
            DetailRow("Şehir", profile.city, null)
        }
        DetailRow(
            label = "Fotoğraf",
            value = "${profile.photos.size} tane",
            hint = "Quiz soruları bu fotoğraflara da dayanabiliyor.",
        )
        DetailRow(
            label = "Zorluk",
            value = profile.solveRate?.let { "%$it geçiyor" } ?: "henüz veri yok",
            hint = when {
                profile.solveRate == null -> "Bu profilin quizini henüz kimse çözmedi."
                profile.solveRate >= 70 -> "Çoğu kişi geçiyor — görece kolay bir quiz."
                profile.solveRate >= 35 -> "Dengeli bir quiz."
                else -> "Az kişi geçebiliyor — zorlu bir quiz."
            },
        )

        Button(
            onClick = { showQuizConfirm = true },
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            modifier = Modifier.fillMaxWidth().padding(top = 20.dp),
        ) {
            Text("Quize başla")
        }

        // Güvenlik eylemleri en altta ve sönük: gerektiğinde bulunabilir olmalı ama
        // ekranın ana eylemiyle yarışmamalı.
        Row(modifier = Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = { showReportDialog = true }, enabled = !uiState.reportSent) {
                Text("Şikayet et", color = colors.textSoft, style = MaterialTheme.typography.bodySmall)
            }
            TextButton(onClick = viewModel::block, enabled = !uiState.blocked) {
                Text("Engelle", color = colors.textSoft, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String, hint: String?) {
    val colors = LocalFarketColors.current
    Row(modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = colors.textSoft,
            modifier = Modifier.width(96.dp),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(value, style = MaterialTheme.typography.bodyLarge)
            if (hint != null) {
                Text(hint, style = MaterialTheme.typography.bodySmall, color = colors.textFaint)
            }
        }
    }
}
