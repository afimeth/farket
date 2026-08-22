package com.farket.app.ui.account

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.data.quiz.PendingRetryRow
import com.farket.app.data.quiz.QuizAllowanceBreakdown
import com.farket.app.data.quiz.QuizRadarRow
import com.farket.app.data.verification.VerificationStatus
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.common.EmptyState
import com.farket.app.ui.profile.setup.IdentityAttributesFields
import com.farket.app.ui.profile.setup.PhotoProcessor
import com.farket.app.ui.profile.setup.rememberIdentityAttributesState
import com.farket.app.ui.theme.FarketPaletteName
import com.farket.app.ui.theme.FarketThemeMode
import com.farket.app.ui.theme.LocalFarketColors
import com.farket.app.ui.theme.PaletteStore
import com.farket.app.ui.theme.ThemeModeToggle
import kotlinx.coroutines.launch

/**
 * Ayarlar ekranı — bkz. proje notları FARKET_PROMPTLAR.md Prompt 9. Şehir değiştirme
 * (Prompt 1'e link), engellenenler listesi, hesabı sil/geri al, verilerimi indir, çıkış yap.
 */
@Composable
fun AccountSettingsScreen(
    onOpenCitySelection: () -> Unit,
    onSignedOut: () -> Unit,
    viewModel: AccountViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showDeleteDialog by remember { mutableStateOf(false) }
    var exportError by remember { mutableStateOf<String?>(null) }

    // İşleme + gönderme ViewModel'de: seçiciden dönerken Activity yeniden yaratılabildiği
    // için kompozisyona bağlı scope'a güvenilemez (bkz. AccountViewModel.submitVerificationFromUri).
    val selfieLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        viewModel.submitVerificationFromUri(context.contentResolver, uri)
    }

    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            viewModel.exportData()
                .onSuccess { json ->
                    runCatching {
                        context.contentResolver.openOutputStream(uri)?.use { it.write(json.toString().toByteArray()) }
                    }.onFailure { exportError = it.message ?: "Dosya yazılamadı" }
                }
                .onFailure { exportError = it.message ?: "Veri dışa aktarılamadı" }
        }
    }

    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Hesabını sil") },
            text = { Text("Hesabın 30 gün boyunca geri alınabilir durumda tutulacak, ardından kalıcı olarak silinecek. Açık konuşmaların kapanacak. Devam etmek istiyor musun?") },
            confirmButton = {
                TextButton(onClick = { showDeleteDialog = false; viewModel.deleteAccount(onSignedOut) }) { Text("Hesabı Sil") }
            },
            dismissButton = { TextButton(onClick = { showDeleteDialog = false }) { Text("Vazgeç") } },
        )
    }

    val colors = LocalFarketColors.current
    val themeMode by PaletteStore.themeMode.collectAsState()
    val isDarkMode = when (themeMode) {
        FarketThemeMode.DARK -> true
        FarketThemeMode.LIGHT -> false
        FarketThemeMode.SYSTEM -> isSystemInDarkTheme()
    }

    // Ekran künye/doğrulama/engellenenler ile zaten uzundu ve kaydırılamıyordu;
    // "Günlük hakkım" ve gizlilik bölümleri eklenince alt kısım tamamen erişilemez
    // hale gelirdi.
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
    ) {
        Text("Ayarlar", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(bottom = 16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                Text("Görünüm", style = MaterialTheme.typography.titleMedium)
                Text(
                    if (isDarkMode) "Gece modu" else "Gündüz modu",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.textSoft,
                )
            }
            ThemeModeToggle(
                isDark = isDarkMode,
                onToggle = { nextIsDark ->
                    PaletteStore.setThemeMode(
                        context,
                        if (nextIsDark) FarketThemeMode.DARK else FarketThemeMode.LIGHT,
                    )
                },
            )
        }

        Text(
            "Renk yönü",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 20.dp, bottom = 8.dp),
        )
        PaletteSwitcher()
        HorizontalDivider(color = colors.line, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))

        val error = uiState.errorMessage ?: exportError
        if (error != null) {
            Text(error, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(bottom = 8.dp))
        }
        if (uiState.message != null) {
            Text(uiState.message!!, color = colors.correct, modifier = Modifier.padding(bottom = 8.dp))
        }

        if (uiState.isLoading) {
            CircularProgressIndicator(color = colors.accent)
            return@Column
        }

        // Şehir değiştirme Keşfet üst barından buraya taşındı: nadiren kullanılan,
        // sonuçları geniş bir işlem (keşif destesi tamamen değişir), her açılışta
        // görünen bir düğme olarak durmasına gerek yok.
        // Tek satır: ikon + kısa açıklama + eylem. Ayrı başlık ve uzun paragraf
        // yerine kompakt tutuldu; ayrıntı zaten şehir seçim ekranında.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp)
                .clickable(onClick = onOpenCitySelection)
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.LocationOn,
                contentDescription = null,
                tint = colors.accent,
                modifier = Modifier.size(22.dp).padding(end = 2.dp),
            )
            Column(modifier = Modifier.weight(1f).padding(start = 10.dp)) {
                Text("Şehir değiştir", style = MaterialTheme.typography.bodyLarge)
                Text(
                    "Yalnızca kendi şehrindeki profilleri keşfedebilirsin.",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.textSoft,
                )
            }
            Text("›", style = MaterialTheme.typography.titleMedium, color = colors.textSoft)
        }
        HorizontalDivider(color = colors.line, modifier = Modifier.padding(top = 8.dp))

        uiState.allowance?.let { allowance ->
            AllowancePanel(allowance)
            HorizontalDivider(color = colors.line, modifier = Modifier.padding(top = 16.dp))
        }

        if (uiState.pendingRetries.isNotEmpty()) {
            PendingRetriesPanel(
                rows = uiState.pendingRetries,
                earlyRetryAvailable = uiState.earlyRetryAvailable,
                earlyRetryNextAt = uiState.earlyRetryNextAt,
                isBusy = uiState.isRedeemingRetry,
                onRedeem = viewModel::redeemEarlyRetry,
            )
            HorizontalDivider(color = colors.line, modifier = Modifier.padding(top = 16.dp))
        }

        if (uiState.quizRadar.isNotEmpty()) {
            QuizRadarPanel(uiState.quizRadar)
            HorizontalDivider(color = colors.line, modifier = Modifier.padding(top = 16.dp))
        }

        Text(
            "Gizlilik",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 24.dp, bottom = 8.dp),
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                Text("Quiz ilerlememi göster", style = MaterialTheme.typography.bodyLarge)
                Text(
                    "Açıkken, birinin quizini çözerken kaçıncı soruda olduğun ve kaç doğru " +
                        "yaptığın o kişiye anlık olarak bildirilir. Kapatırsan yalnızca sonuç " +
                        "paylaşılır.",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.textSoft,
                )
            }
            Switch(
                checked = uiState.shareQuizProgress,
                onCheckedChange = viewModel::setShareQuizProgress,
                enabled = !uiState.isSavingPrivacy,
            )
        }

        OutlinedButton(
            onClick = { exportLauncher.launch("farket-verilerim.json") },
            shape = RoundedCornerShape(14.dp),
            border = BorderStroke(1.dp, colors.line),
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
            enabled = !uiState.isBusy,
        ) {
            Text("Verilerimi İndir")
        }

        if (uiState.isAccountDeleted) {
            Button(
                onClick = viewModel::restoreAccount,
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                enabled = !uiState.isBusy,
            ) {
                Text("Hesabı Geri Al")
            }
        } else {
            OutlinedButton(
                onClick = { showDeleteDialog = true },
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.error),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                enabled = !uiState.isBusy,
            ) {
                Text("Hesabı Sil")
            }
        }

        TextButton(
            onClick = { viewModel.signOut(onSignedOut) },
            modifier = Modifier.padding(top = 12.dp),
        ) {
            Text("Çıkış Yap", color = colors.textSoft)
        }

        Text(
            "Künye bilgilerim",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 24.dp, bottom = 8.dp),
        )
        val attributesState = rememberIdentityAttributesState(uiState.identityAttributes)
        IdentityAttributesFields(attributesState)
        Button(
            onClick = { viewModel.saveIdentityAttributes(attributesState.drafts()) },
            enabled = !uiState.isSavingIdentityAttributes,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        ) {
            if (uiState.isSavingIdentityAttributes) {
                CircularProgressIndicator(color = colors.accentInk, modifier = Modifier.padding(2.dp))
            } else {
                Text("Kaydet")
            }
        }

        Text(
            "Doğrulama",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 24.dp, bottom = 8.dp),
        )
        when (uiState.verificationStatus) {
            VerificationStatus.VERIFIED -> Text("Doğrulanmış hesap.", color = colors.correct)
            VerificationStatus.PENDING -> Text("Başvurun inceleniyor.", color = colors.textSoft)
            VerificationStatus.NONE, VerificationStatus.REJECTED -> {
                if (uiState.verificationStatus == VerificationStatus.REJECTED) {
                    Text(
                        "Başvurun reddedildi. Tekrar deneyebilirsin.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(bottom = 8.dp),
                    )
                } else {
                    Text(
                        "Bir selfie ile hesabını doğrula — profilinde doğrulanmış rozeti görünür.",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.textSoft,
                        modifier = Modifier.padding(bottom = 8.dp),
                    )
                }
                if (uiState.isSubmittingVerification) {
                    CircularProgressIndicator(color = colors.accent)
                } else {
                    OutlinedButton(
                        onClick = { selfieLauncher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                        shape = RoundedCornerShape(14.dp),
                        border = BorderStroke(1.dp, colors.line),
                    ) {
                        Text("Selfie ile doğrula")
                    }
                }
            }
        }

        Text(
            "Engellenenler",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 24.dp, bottom = 8.dp),
        )
        if (uiState.blockedUsers.isEmpty()) {
            EmptyState("Kimseyi engellemedin.")
        } else {
            uiState.blockedUsers.forEach { blocked ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("@${blocked.username}")
                    TextButton(onClick = { viewModel.unblock(blocked.profileId) }) { Text("Engeli Kaldır") }
                }
            }
        }
    }
}

/** `get_quiz_allowance_breakdown`'daki koşul anahtarı -> başlık + nasıl kazanılır. */
private fun conditionLabel(key: String): Pair<String, String> = when (key) {
    "verified" ->
        "Doğrulanmış hesap" to "Aşağıdan selfie ile doğrula."
    "no_pending_request" ->
        "Bekleyen mesaj isteğin yok" to "Sana gelen istekleri cevapla."
    "quiz_health" ->
        "Quizin dengeli" to "Soruların ne herkesin bildiği kadar kolay ne de kimsenin bilemeyeceği kadar zor olmalı."
    "profile_complete" ->
        "Profilin tam" to "7 fotoğraf, en az 5 serbest soru ve bir gizli kart."
    else -> key to ""
}

/**
 * Günlük quiz hakkının nereden geldiğini gösterir. Hesap yıllardır arkada çalışıyordu
 * ama kullanıcı ne kadar hakkı olduğunu, hele "bir tane daha nasıl kazanırım"ı hiç
 * göremiyordu — görünmeyen ilerleme ilerleme değil.
 */
@Composable
private fun AllowancePanel(allowance: QuizAllowanceBreakdown) {
    val colors = LocalFarketColors.current

    Text(
        "Günlük hakkım",
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(top = 24.dp, bottom = 4.dp),
    )
    Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.padding(bottom = 2.dp)) {
        Text(
            "${allowance.remaining}",
            style = MaterialTheme.typography.headlineSmall,
            color = colors.accent,
        )
        Text(
            " / ${allowance.allowance} quiz hakkı kaldı",
            style = MaterialTheme.typography.bodyLarge,
            color = colors.textSoft,
            modifier = Modifier.padding(bottom = 3.dp),
        )
    }
    Text(
        "Herkes ${allowance.base} hakla başlar, aşağıdaki her madde bir hak daha ekler " +
            "(en fazla ${allowance.cap}).",
        style = MaterialTheme.typography.bodySmall,
        color = colors.textSoft,
        modifier = Modifier.padding(bottom = 12.dp),
    )

    allowance.conditions.forEach { condition ->
        val (title, howTo) = conditionLabel(condition.key)
        Row(modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
            Text(
                if (condition.earned) "✓" else "○",
                color = if (condition.earned) colors.correct else colors.textFaint,
                modifier = Modifier.padding(end = 10.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "$title  +${condition.bonus}",
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (condition.earned) colors.text else colors.textFaint,
                )
                if (!condition.earned) {
                    Text(howTo, style = MaterialTheme.typography.bodySmall, color = colors.textSoft)
                    // Somut sayıları göster: "profilin tam değil" demek yerine nesi eksik olduğunu.
                    val detail = when (condition.key) {
                        // Yalnızca EKSİK olan parçalar listeleniyor: karşılanmış bir
                        // şartı "6/5 serbest soru" diye göstermek kafa karıştırıyordu.
                        "profile_complete" -> listOfNotNull(
                            condition.photoCount?.let { if (it >= 7) null else "$it/7 fotoğraf" },
                            condition.customQuestionCount?.let { if (it >= 5) null else "$it/5 serbest soru" },
                            condition.hasSecretCard?.let { if (it) null else "gizli kart yok" },
                        ).joinToString(" · ").ifBlank { null }
                        "quiz_health" -> condition.solveRate?.let { "şu anki çözülme oranın %$it" }
                        else -> null
                    }
                    if (detail != null) {
                        Text(detail, style = MaterialTheme.typography.bodySmall, color = colors.textFaint)
                    }
                }
            }
        }
    }

    if (allowance.lockedForToday) {
        Text(
            "Bugünkü hakkın günün ilk quizinde sabitlendi — yeni kazandığın maddeler yarın yansır.",
            style = MaterialTheme.typography.bodySmall,
            color = colors.textFaint,
        )
    }
}

private fun formatDateTime(iso: String?): String? = iso?.let {
    runCatching {
        java.time.OffsetDateTime.parse(it)
            .atZoneSameInstant(java.time.ZoneId.of("Europe/Istanbul"))
            .format(java.time.format.DateTimeFormatter.ofPattern("d MMMM, HH:mm", java.util.Locale("tr")))
    }.getOrNull()
}

/**
 * Beklemedeki profiller ve haftalık "erken ikinci şans" hakkı.
 *
 * Ceza yapısı kasıtlı olarak korunuyor: bekleme süreleri, kredi maliyeti ve ikinci
 * denemede tavan skorun 8'de kalması aynen duruyor. Burada eklenen tek şey, haftada
 * bir kez beklemeyi erken bitirebilme — cezanın telafisi olmayan bir döngü zorlamaya
 * dönüşüyor.
 */
@Composable
private fun PendingRetriesPanel(
    rows: List<PendingRetryRow>,
    earlyRetryAvailable: Boolean,
    earlyRetryNextAt: String?,
    isBusy: Boolean,
    onRedeem: (String) -> Unit,
) {
    val colors = LocalFarketColors.current

    Text(
        "Beklemedeki profiller",
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(top = 24.dp, bottom = 4.dp),
    )
    Text(
        if (earlyRetryAvailable) {
            "Haftada bir kez, bir profilin beklemesini erken bitirebilirsin. " +
                "İkinci denemede en fazla 8 doğru sayılır ve kredi yine harcanır."
        } else {
            val next = formatDateTime(earlyRetryNextAt)
            if (next != null) "Erken açma hakkını bu hafta kullandın. Yenilenme: $next."
            else "Erken açma hakkını bu hafta kullandın."
        },
        style = MaterialTheme.typography.bodySmall,
        color = colors.textSoft,
        modifier = Modifier.padding(bottom = 12.dp),
    )

    rows.forEach { row ->
        Row(
            modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                Text("@${row.username ?: "?"}", style = MaterialTheme.typography.bodyLarge)
                Text(
                    buildString {
                        row.firstAttemptScore?.let { append("İlk denemende $it doğru. ") }
                        if (row.isAvailableNow) {
                            append("Şimdi tekrar deneyebilirsin (${row.retryCost} kredi).")
                        } else {
                            append("Açılış: ${formatDateTime(row.availableAt) ?: "yakında"}")
                        }
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = if (row.isAvailableNow) colors.correct else colors.textSoft,
                )
            }
            if (!row.isAvailableNow && earlyRetryAvailable) {
                TextButton(onClick = { onRedeem(row.profileId) }, enabled = !isBusy) {
                    Text("Şimdi aç", color = colors.accent)
                }
            }
        }
    }
}

/**
 * Kendi sorularının nasıl gittiği. `get_quiz_radar` uzun süredir backend'de duruyordu
 * ama hiçbir ekranda kullanılmıyordu.
 */
@Composable
private fun QuizRadarPanel(rows: List<QuizRadarRow>) {
    val colors = LocalFarketColors.current

    Text(
        "Sorularım nasıl gidiyor?",
        style = MaterialTheme.typography.titleMedium,
        modifier = Modifier.padding(top = 24.dp, bottom = 4.dp),
    )
    Text(
        "Hangi soruların ayırt edici, hangileri herkesin bildiği kadar kolay. " +
            "\"Ölü\" işaretli sorular otomatik olarak devre dışı bırakıldı.",
        style = MaterialTheme.typography.bodySmall,
        color = colors.textSoft,
        modifier = Modifier.padding(bottom = 12.dp),
    )

    rows.forEach { row ->
        Row(
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                Text(row.body, style = MaterialTheme.typography.bodyLarge)
                Text(
                    "${row.shownCount} kez soruldu",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.textFaint,
                )
            }
            Text(
                when {
                    row.isDead -> "ölü"
                    row.correctRate != null -> "%${row.correctRate}"
                    else -> "—"
                },
                style = MaterialTheme.typography.bodyLarge,
                color = if (row.isDead) MaterialTheme.colorScheme.error else colors.textSoft,
            )
        }
    }
}

@Composable
private fun PaletteSwitcher() {
    val context = LocalContext.current
    val colors = LocalFarketColors.current
    val current by PaletteStore.palette.collectAsState()
    val options = listOf(
        FarketPaletteName.ODA to "Oda",
        FarketPaletteName.FENER to "Fener",
        FarketPaletteName.ALACA to "Alaca",
    )

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { (paletteName, label) ->
            val selected = current == paletteName
            OutlinedButton(
                onClick = { PaletteStore.set(context, paletteName) },
                shape = RoundedCornerShape(999.dp),
                border = BorderStroke(1.dp, if (selected) colors.accent else colors.line),
                colors = if (selected) {
                    ButtonDefaults.outlinedButtonColors(containerColor = colors.accent, contentColor = colors.accentInk)
                } else {
                    ButtonDefaults.outlinedButtonColors(contentColor = colors.textSoft)
                },
            ) {
                Text(label)
            }
        }
    }
}
