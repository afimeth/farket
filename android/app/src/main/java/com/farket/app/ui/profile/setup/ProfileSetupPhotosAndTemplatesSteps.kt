package com.farket.app.ui.profile.setup

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.farket.app.data.profile.QuestionTemplateRow
import com.farket.app.ui.theme.LocalFarketColors
import kotlinx.coroutines.launch

@Composable
internal fun PhotosStep(uiState: ProfileSetupUiState, viewModel: ProfileSetupViewModel) {
    val context = LocalContext.current
    val colors = LocalFarketColors.current
    // PickMultipleVisualMedia maxItems > 1 gerektiriyor (bkz. PhotosScreen.kt'deki aynı düzeltme).
    val remainingSlots = (7 - uiState.photoCount).coerceAtLeast(2)

    // İşleme ve yükleme bilerek ViewModel'e devredildi. Burada `rememberCoroutineScope()`
    // kullanmak yüklemeyi sessizce kırıyordu: seçiciden dönerken Activity yeniden
    // yaratılabildiği için kompozisyona bağlı scope iptal oluyor ve gövde hiç çalışmıyor
    // (ayrıntı: ProfileSetupViewModel.addPhotosFromUris).
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(remainingSlots),
    ) { uris ->
        viewModel.addPhotosFromUris(context.contentResolver, uris)
    }

    Text("Fotoğraflar", style = MaterialTheme.typography.headlineSmall)
    Text(
        "5 ile 7 arasında fotoğraf yükle. Bunlar quiz boyunca gizli kalacak.",
        style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.padding(top = 8.dp, bottom = 4.dp),
    )
    // Yerel test notu: yeni yüklenen fotoğraflar onay bekler (pending) — moderasyon aracı
    // olmadığı için yerelde görünmüyorsa Supabase Studio'dan elle onaylanması gerekebilir.
    Text(
        "Onaylanması biraz sürebilir.",
        style = MaterialTheme.typography.labelSmall,
        color = colors.textFaint,
        modifier = Modifier.padding(bottom = 12.dp),
    )

    Text("${uiState.photoCount}/7 yüklendi (en az 5 gerekli)", style = MaterialTheme.typography.bodyMedium)

    // İşleme/yükleme artık ViewModel'de olduğu için ilerleme göstergesi de oradan geliyor.
    if (uiState.isLoading) {
        CircularProgressIndicator(color = colors.accent, modifier = Modifier.padding(top = 12.dp))
    } else if (uiState.photoCount < 7) {
        OutlinedButton(
            onClick = { launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            shape = RoundedCornerShape(14.dp),
            border = BorderStroke(1.dp, colors.line),
            modifier = Modifier.padding(top = 12.dp),
        ) {
            Text("Fotoğraf ekle")
        }
    }

    StepActions(
        label = "İleri",
        enabled = uiState.canAdvanceFromPhotos,
        onClick = viewModel::finishPhotosStep,
        blockedReason = "En az 5 fotoğraf gerekiyor — ${(5 - uiState.photoCount).coerceAtLeast(0)} tane daha ekle.",
    )
}

@Composable
internal fun TemplateAnswersStep(
    templates: List<QuestionTemplateRow>,
    answered: Set<Int>,
    optionsByTemplateId: Map<Int, TemplateOptionsState>,
    minRequired: Int,
    canAdvance: Boolean,
    viewModel: ProfileSetupViewModel,
    isAct2Hard: Boolean,
    onNext: () -> Unit,
) {
    val colors = LocalFarketColors.current

    // Aynı anda tek soru açık (akordiyon): tüm şıkların birden açık durması ekranı
    // gereksiz uzatıyordu. Başlangıçta ilk cevaplanmamış soru açılır.
    var expandedId by remember(templates.map { it.id }) {
        mutableStateOf(templates.firstOrNull { it.id !in answered }?.id)
    }

    Text(
        text = if (isAct2Hard) "Zor sorular (2. perde)" else "Kalıp sorular (1. perde)",
        style = MaterialTheme.typography.headlineSmall,
    )

    // Gereken minimum, ekranın en görünür yerinde: kaç tane cevaplandı, kaç tane
    // kaldı ve yeterli sayıya ulaşılıp ulaşılmadığı tek bakışta okunmalı.
    Row(verticalAlignment = Alignment.Bottom, modifier = Modifier.padding(top = 10.dp)) {
        Text(
            "${answered.size}",
            style = MaterialTheme.typography.headlineSmall,
            color = if (canAdvance) colors.correct else colors.accent,
        )
        Text(
            " / $minRequired soru cevaplandı",
            style = MaterialTheme.typography.bodyLarge,
            color = colors.textSoft,
            modifier = Modifier.padding(bottom = 3.dp),
        )
    }
    LinearProgressIndicator(
        progress = { (answered.size.toFloat() / minRequired).coerceIn(0f, 1f) },
        color = if (canAdvance) colors.correct else colors.accent,
        trackColor = colors.line,
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
    )
    Text(
        text = if (canAdvance) {
            "En az $minRequired soru şartını karşıladın. İstersen devam et, istersen " +
                "daha fazlasını cevapla — ne kadar çok soru, o kadar ayırt edici bir quiz."
        } else {
            "Devam edebilmen için en az $minRequired soru gerekiyor. " +
                "${minRequired - answered.size} soru kaldı."
        },
        style = MaterialTheme.typography.bodySmall,
        color = if (canAdvance) colors.correct else colors.textSoft,
        modifier = Modifier.padding(top = 8.dp, bottom = 12.dp),
    )

    Column {
        templates.forEach { template ->
            TemplateQuestionCard(
                template = template,
                isAnswered = template.id in answered,
                options = optionsByTemplateId[template.id],
                isExpanded = expandedId == template.id,
                onToggle = { expandedId = if (expandedId == template.id) null else template.id },
                onAppear = { viewModel.loadOptionsFor(template) },
                onAnswer = { optionId, itemId ->
                    viewModel.answerTemplate(template.id, isAct2Hard, optionId, itemId)
                    // Cevaplayınca bu soru kapanıp sıradaki cevaplanmamış soru açılır;
                    // kullanıcı listede elle gezinmek zorunda kalmasın.
                    expandedId = templates.firstOrNull { it.id != template.id && it.id !in answered }?.id
                },
            )
        }
    }

    StepActions(
        label = "İleri",
        enabled = canAdvance,
        onClick = onNext,
        blockedReason = "En az $minRequired soru gerekiyor — ${(minRequired - answered.size).coerceAtLeast(0)} tane daha cevapla.",
    )
}

@Composable
private fun TemplateQuestionCard(
    template: QuestionTemplateRow,
    isAnswered: Boolean,
    options: TemplateOptionsState?,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    onAppear: () -> Unit,
    onAnswer: (optionId: Int?, itemId: Int?) -> Unit,
) {
    // Şıklar yalnızca soru açıldığında yükleniyor: eskiden ekrandaki her soru için
    // açılış anında ayrı bir istek gidiyordu.
    LaunchedEffect(template.id, isExpanded) { if (isExpanded) onAppear() }
    var selectedId by remember(template.id) { mutableStateOf<Int?>(null) }
    val colors = LocalFarketColors.current

    Card(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        border = BorderStroke(1.dp, if (isExpanded) colors.accent else colors.line),
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            // Başlık satırının tamamı açma/kapama düğmesi.
            Row(
                modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
                    Text(template.body, style = MaterialTheme.typography.bodyLarge)
                    if (isAnswered) {
                        Text(
                            "Cevaplandı",
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.correct,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
                Text(
                    if (isExpanded) "▲" else "▼",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.textSoft,
                )
            }

            if (!isExpanded) return@Column

            val fixedOptions = options?.fixedOptions
            val taxonomyItems = options?.taxonomyItems
            val radioColors = RadioButtonDefaults.colors(selectedColor = colors.accent)

            when {
                fixedOptions != null -> fixedOptions.forEach { option ->
                    Row(modifier = Modifier.fillMaxWidth()) {
                        RadioButton(
                            selected = selectedId == option.id,
                            onClick = {
                                selectedId = option.id
                                onAnswer(option.id, null)
                            },
                            colors = radioColors,
                        )
                        Text(option.body, modifier = Modifier.padding(top = 12.dp))
                    }
                }
                taxonomyItems != null -> taxonomyItems.forEach { item ->
                    Row(modifier = Modifier.fillMaxWidth()) {
                        RadioButton(
                            selected = selectedId == item.id,
                            onClick = {
                                selectedId = item.id
                                onAnswer(null, item.id)
                            },
                            colors = radioColors,
                        )
                        Text(item.label, modifier = Modifier.padding(top = 12.dp))
                    }
                }
                else -> CircularProgressIndicator(color = colors.accent, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}

@Composable
internal fun CustomQuestionStep(onSubmit: (body: String, options: List<String>, correctIndex: Int) -> Unit) {
    val colors = LocalFarketColors.current
    var questionBody by remember { mutableStateOf("") }
    var optionA by remember { mutableStateOf("") }
    var optionB by remember { mutableStateOf("") }
    var correctIndex by remember { mutableStateOf(0) }
    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedBorderColor = colors.accent,
        unfocusedBorderColor = colors.line,
        focusedLabelColor = colors.accent,
    )
    val radioColors = RadioButtonDefaults.colors(selectedColor = colors.accent)

    Text("Serbest soru", style = MaterialTheme.typography.headlineSmall)
    Text(
        "Kendi sorunu yaz (telefon numarası, sosyal medya paylaşımı ya da şık yönlendirmesi " +
            "içeremez).",
        style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
    )

    OutlinedTextField(
        value = questionBody,
        onValueChange = { questionBody = it },
        label = { Text("Soru") },
        shape = RoundedCornerShape(14.dp),
        colors = fieldColors,
        modifier = Modifier.fillMaxWidth(),
    )

    Row(modifier = Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        RadioButton(selected = correctIndex == 0, onClick = { correctIndex = 0 }, colors = radioColors)
        OutlinedTextField(
            value = optionA,
            onValueChange = { optionA = it },
            label = { Text("Şık 1 (doğru işaretle)") },
            shape = RoundedCornerShape(14.dp),
            colors = fieldColors,
            modifier = Modifier.fillMaxWidth(),
        )
    }
    Row(modifier = Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        RadioButton(selected = correctIndex == 1, onClick = { correctIndex = 1 }, colors = radioColors)
        OutlinedTextField(
            value = optionB,
            onValueChange = { optionB = it },
            label = { Text("Şık 2") },
            shape = RoundedCornerShape(14.dp),
            colors = fieldColors,
            modifier = Modifier.fillMaxWidth(),
        )
    }

    val missingCustom = listOfNotNull(
        "soru metni".takeIf { questionBody.isBlank() },
        "1. şık".takeIf { optionA.isBlank() },
        "2. şık".takeIf { optionB.isBlank() },
    )

    StepActions(
        label = "İleri",
        enabled = missingCustom.isEmpty(),
        onClick = { onSubmit(questionBody, listOf(optionA, optionB), correctIndex) },
        blockedReason = "Eksik: ${missingCustom.joinToString(", ")}. Ayrıca doğru cevabın " +
            "hangi şık olduğunu solundaki yuvarlaktan işaretle.",
    )
}
