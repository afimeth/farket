package com.farket.app.ui.profile.setup

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.theme.LocalFarketColors

/**
 * Profil kurulum sihirbazı — bkz. proje notları FARKET_PROMPTLAR.md Prompt 3. Backend Görev 6
 * tamamlandığı için tüm adımlar gerçek RPC'lerle/doğrudan Postgrest insert-update'lerle çalışır,
 * mock veri yok.
 */
@Composable
fun ProfileSetupScreen(
    onPublished: () -> Unit,
    viewModel: ProfileSetupViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(uiState.publishResult) {
        if (uiState.publishResult?.status == "published") {
            onPublished()
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        StepProgress(step = uiState.step)

        if (uiState.errorMessage != null) {
            Text(
                text = uiState.errorMessage!!,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(top = 12.dp),
        ) {
            if (!uiState.hasResolvedInitialStep) {
                // Sunucudaki mevcut ilerleme henüz okunmadı, hangi adımda olunacağı bilinmiyor —
                // burada gösterilecek gerçek bir adım (korunacak bir form durumu) yok.
                CircularProgressIndicator(color = LocalFarketColors.current.accent)
            } else {
                // Bulgu (frontend, kritik — canlı testte bulundu): önceden bu blok
                // `if (isLoading) Spinner else when(step){...}` şeklindeydi — her form
                // gönderiminde (başarısız olsa bile) adım composable'ı bir anlığına
                // Spinner'la DEĞİŞTİRİLİYOR, bu da Compose'un `remember` ettiği tüm alan
                // durumunu (kullanıcının az önce yazdığı her şey) yok ediyordu. Artık adım
                // composable'ı asla sökülmüyor; yükleniyor durumu yalnızca ince bir üst katman.
                Box {
                    Column {
                        when (uiState.step) {
                        SetupStep.BASIC_INFO -> BasicInfoStep(uiState, viewModel::submitBasicInfo)
                        SetupStep.AGE_ATTESTATION -> AgeAttestationStep(viewModel::confirmAge)
                        SetupStep.USERNAME -> UsernameStep(viewModel::submitUsername)
                        SetupStep.IDENTITY_CARD -> IdentityCardStep(viewModel::submitIdentityCard)
                        SetupStep.IDENTITY_ATTRIBUTES -> IdentityAttributesStep(
                            initial = uiState.identityAttributes,
                            onSubmit = viewModel::submitIdentityAttributes,
                        )
                        SetupStep.PHOTOS -> PhotosStep(uiState, viewModel)
                        SetupStep.TEMPLATE_ANSWERS_ACT1 -> TemplateAnswersStep(
                            templates = uiState.act1Templates,
                            answered = uiState.act1Answered,
                            optionsByTemplateId = uiState.optionsByTemplateId,
                            minRequired = 7,
                            canAdvance = uiState.canAdvanceFromAct1,
                            viewModel = viewModel,
                            isAct2Hard = false,
                            onNext = viewModel::finishAct1Step,
                        )
                        SetupStep.TEMPLATE_ANSWERS_ACT2_HARD -> TemplateAnswersStep(
                            templates = uiState.act2HardTemplates,
                            answered = uiState.act2HardAnswered,
                            optionsByTemplateId = uiState.optionsByTemplateId,
                            minRequired = 3,
                            canAdvance = uiState.canAdvanceFromAct2Hard,
                            viewModel = viewModel,
                            isAct2Hard = true,
                            onNext = viewModel::finishAct2HardStep,
                        )
                        SetupStep.CUSTOM_QUESTION -> CustomQuestionStep(viewModel::submitCustomQuestion)
                        SetupStep.PUBLISH -> PublishStep(uiState, viewModel::publish)
                        }
                    }
                    if (uiState.isLoading) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(LocalFarketColors.current.bg.copy(alpha = 0.6f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator(color = LocalFarketColors.current.accent)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun StepProgress(step: SetupStep) {
    val colors = LocalFarketColors.current
    val steps = SetupStep.entries
    val progress = (steps.indexOf(step) + 1f) / steps.size
    LinearProgressIndicator(
        progress = { progress },
        color = colors.accent,
        trackColor = colors.veil,
        modifier = Modifier.fillMaxWidth(),
    )
    Text(
        text = "${steps.indexOf(step) + 1}/${steps.size}",
        style = MaterialTheme.typography.labelMedium,
        modifier = Modifier.padding(top = 4.dp),
    )
}

/**
 * Adım sonundaki ilerleme butonu.
 *
 * [blockedReason] buton pasifken hemen üstünde gösterilir. Eksik şartı söylemeyen
 * pasif bir buton kullanıcıyı çıkışsız bırakıyor: şart adımın başında yazsa bile,
 * alanları doldurmak için aşağı kaydırınca o metin ekrandan çıkıyor ve butonun neden
 * pasif olduğu belirsiz kalıyor (canlı testte künye bilgileri adımında birebir yaşandı).
 */
@Composable
internal fun StepActions(
    label: String,
    enabled: Boolean,
    onClick: () -> Unit,
    blockedReason: String? = null,
) {
    val colors = LocalFarketColors.current
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (!enabled && blockedReason != null) {
            Text(
                blockedReason,
                style = MaterialTheme.typography.bodySmall,
                color = colors.textSoft,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        Button(
            onClick = onClick,
            enabled = enabled,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(label)
        }
    }
}
