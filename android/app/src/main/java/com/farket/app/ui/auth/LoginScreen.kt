package com.farket.app.ui.auth

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.BuildConfig
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.theme.LocalFarketColors

/**
 * Düzen — design-canvas/Giris.dc.html'deki orijinal prototiple birebir: üst blok (marka/başlık)
 * ekranın üstüne yakın sabit, alt blok (form) ekranın en altına yaslı, aradaki boşluk esnek bir
 * spacer.
 *
 * Giriş link-tabanlı (beta kararı, 21 Ağustos — Cloud ücretsiz plan e-posta şablonunu
 * özelleştirmeye izin vermediği için kod-girişi yerine bu akış kullanılıyor): adres gir →
 * posta kutusuna gelen bağlantıya dokun → uygulama otomatik açılıp giriş yapar (bkz.
 * MainActivity.handleAuthDeeplink). Bu ekran linkin doğrulanmasını beklemez; başarı global
 * sessionStatus akışından gelir.
 */
@Composable
fun LoginScreen(
    viewModel: AuthViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalFarketColors.current

    val waitingEmail = when (val state = uiState) {
        is LoginUiState.WaitingForLink -> state.email
        is LoginUiState.EnterTestCode -> state.email
        is LoginUiState.Error -> state.email
        else -> null
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 28.dp, vertical = 34.dp),
    ) {
        if (waitingEmail == null) {
            androidx.compose.foundation.layout.Row(
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
            ) {
                androidx.compose.foundation.Image(
                    painter = androidx.compose.ui.res.painterResource(com.farket.app.R.drawable.ic_launcher_foreground),
                    contentDescription = null,
                    modifier = Modifier.size(36.dp).offset(y = (-3).dp),
                )
                Text(
                    text = "farket",
                    style = MaterialTheme.typography.headlineMedium,
                    color = colors.accent,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
            Text(
                text = "Görmeden önce fark et.",
                style = MaterialTheme.typography.bodyLarge,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 8.dp),
            )
        } else if (uiState is LoginUiState.EnterTestCode || (uiState as? LoginUiState.Error)?.isTestCodeFlow == true) {
            Text(text = "Test kodunu gir", style = MaterialTheme.typography.titleLarge)
            Text(
                text = "$waitingEmail — beta test aşamasında mail beklemene gerek yok, aşağıdaki sabit kodu gir.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 6.dp),
            )
        } else {
            Text(text = "E-postana bir bağlantı gönderdik", style = MaterialTheme.typography.titleLarge)
            Text(
                text = "$waitingEmail adresine gelen e-postadaki bağlantıya dokun, uygulama otomatik açılacak.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 6.dp),
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        if (uiState is LoginUiState.Error) {
            Text(
                text = (uiState as LoginUiState.Error).message,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(bottom = 16.dp),
            )
        }

        when (val state = uiState) {
            is LoginUiState.EnterEmail, is LoginUiState.SendingLink -> {
                EmailStep(
                    isLoading = state is LoginUiState.SendingLink,
                    onSubmitLink = viewModel::sendLoginLink,
                    onUseTestCode = viewModel::goToTestCodeEntry,
                )
            }
            is LoginUiState.WaitingForLink -> {
                WaitingStep(onChangeEmail = viewModel::backToEmailEntry)
            }
            is LoginUiState.EnterTestCode -> {
                TestCodeStep(
                    email = state.email,
                    isSubmitting = state.submitting,
                    onSubmit = { code -> viewModel.submitTestCode(state.email, code) },
                    onChangeEmail = viewModel::backToEmailEntry,
                )
            }
            is LoginUiState.Error -> {
                val email = state.email
                when {
                    email == null -> EmailStep(
                        isLoading = false,
                        onSubmitLink = viewModel::sendLoginLink,
                        onUseTestCode = viewModel::goToTestCodeEntry,
                    )
                    state.isTestCodeFlow -> TestCodeStep(
                        email = email,
                        isSubmitting = false,
                        onSubmit = { code -> viewModel.submitTestCode(email, code) },
                        onChangeEmail = viewModel::backToEmailEntry,
                    )
                    else -> WaitingStep(onChangeEmail = viewModel::backToEmailEntry)
                }
            }
        }
    }
}

@Composable
private fun EmailStep(
    isLoading: Boolean,
    onSubmitLink: (String) -> Unit,
    onUseTestCode: (String) -> Unit,
) {
    val colors = LocalFarketColors.current
    var email by remember { mutableStateOf("") }
    val isValid = email.isNotBlank() && email.contains("@")

    OutlinedTextField(
        value = email,
        onValueChange = { email = it },
        label = { Text("E-posta adresi") },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.line,
            focusedLabelColor = colors.accent,
        ),
        modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
    )

    Text(
        text = if (BuildConfig.BETA_TEST_LOGIN) {
            "Beta aşamasında kendi e-posta adresini gir ve \"Devam et\"e dokun. Sana mail " +
                "gönderilmeyecek — doğrulama kodu olarak her zaman $BETA_TEST_LOGIN_CODE yaz."
        } else {
            "E-posta adresini gir; sana tek kullanımlık bir giriş bağlantısı göndereceğiz. " +
                "Şifre yok, bağlantıya dokunman yeterli."
        },
        style = MaterialTheme.typography.bodySmall,
        color = colors.textSoft,
        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
    )

    if (isLoading) {
        CircularProgressIndicator(color = colors.accent)
    } else if (BuildConfig.BETA_TEST_LOGIN) {
        // Yerel/geliştirme derlemesinde birincil yol sabit kodla giriş: gerçek magic-link maili
        // yalnızca doğrulanmış bir gönderen domaini olduğunda çalışıyor.
        Button(
            onClick = { onUseTestCode(email) },
            enabled = isValid,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Devam et")
        }
        TextButton(
            onClick = { onSubmitLink(email) },
            enabled = isValid,
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        ) {
            Text("Bunun yerine mail ile giriş bağlantısı gönder", color = colors.textSoft)
        }
    } else {
        // Herkese açık derlemede tek yol mail bağlantısı — sabit kodlu kısayol yok.
        Button(
            onClick = { onSubmitLink(email) },
            enabled = isValid,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Giriş bağlantısı gönder")
        }
    }
}

@Composable
private fun TestCodeStep(
    email: String,
    isSubmitting: Boolean,
    onSubmit: (String) -> Unit,
    onChangeEmail: () -> Unit,
) {
    val colors = LocalFarketColors.current
    var code by remember { mutableStateOf("") }

    Text(
        text = "Test kodu: $BETA_TEST_LOGIN_CODE",
        style = MaterialTheme.typography.bodyMedium,
        color = colors.accent,
        modifier = Modifier.padding(bottom = 12.dp),
    )

    OutlinedTextField(
        value = code,
        onValueChange = { code = it },
        label = { Text("Kod") },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.line,
            focusedLabelColor = colors.accent,
        ),
        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
    )

    if (isSubmitting) {
        CircularProgressIndicator(color = colors.accent)
    } else {
        Button(
            onClick = { onSubmit(code) },
            enabled = code.isNotBlank(),
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Giriş Yap")
        }
        TextButton(onClick = onChangeEmail, modifier = Modifier.fillMaxWidth()) {
            Text("Adresi değiştir", color = colors.textSoft)
        }
    }
}

@Composable
private fun WaitingStep(onChangeEmail: () -> Unit) {
    val colors = LocalFarketColors.current
    CircularProgressIndicator(color = colors.accent, modifier = Modifier.padding(bottom = 20.dp))
    TextButton(onClick = onChangeEmail, modifier = Modifier.fillMaxWidth()) {
        Text("Adresi değiştir", color = colors.textSoft)
    }
}
