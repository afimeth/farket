package com.farket.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.lifecycle.lifecycleScope
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.farket.app.data.SupabaseClientProvider
import com.farket.app.data.auth.EmailAuthRepository
import com.farket.app.data.profile.ProfileRepository
import com.farket.app.data.profile.ProfileStatus
import com.farket.app.navigation.FarketNavGraph
import com.farket.app.navigation.Routes
import com.farket.app.ui.onboarding.OnboardingStore
import com.farket.app.ui.theme.FarketTheme
import com.farket.app.ui.theme.FarketThemeMode
import com.farket.app.ui.theme.PaletteStore
import io.github.jan.supabase.auth.handleDeeplinks
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PaletteStore.init(applicationContext)
        setContent {
            FarketApp()
        }
        handleAuthDeeplink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthDeeplink(intent)
    }

    // E-posta giriş linkine (farket://login-callback, bkz. SupabaseClientProvider)
    // dokunulunca uygulama bu intent ile açılır/öne gelir; SDK URL'deki token'ları
    // çözüp oturumu kurar. Bu global sessionStatus'u Authenticated'e çeviriyor,
    // FarketApp() zaten bunu izlediği için LoginScreen otomatik geride kalır.
    private fun handleAuthDeeplink(intent: Intent?) {
        intent ?: return
        if (intent.data == null) return
        lifecycleScope.launch {
            runCatching {
                SupabaseClientProvider.client.handleDeeplinks(intent)
            }
        }
    }
}

@Composable
private fun FarketApp() {
    val authRepository = remember { EmailAuthRepository(SupabaseClientProvider.client) }
    val sessionStatus by authRepository.sessionStatus.collectAsState()
    val palette by PaletteStore.palette.collectAsState()
    val themeMode by PaletteStore.themeMode.collectAsState()
    // Tema eskiden `darkTheme = true` ile sabitlenmişti; paletlerin açık varyantları
    // tanımlı olduğu halde hiç kullanılmıyordu. Artık kullanıcı seçiyor.
    val isDark = when (themeMode) {
        FarketThemeMode.DARK -> true
        FarketThemeMode.LIGHT -> false
        FarketThemeMode.SYSTEM -> isSystemInDarkTheme()
    }

    FarketTheme(palette = palette, darkTheme = isDark) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = com.farket.app.ui.theme.LocalFarketColors.current.bg,
        ) {
            // SDK, saklanmış oturumu diskten async yüklüyor; ilk karar verilmeden önce
            // Initializing durumunun geçmesini bekliyoruz, aksi halde geçerli bir oturum
            // varken bile kullanıcı her açılışta login ekranına düşer.
            when (sessionStatus) {
                is SessionStatus.Initializing -> {
                    LoadingIndicator()
                }
                is SessionStatus.Authenticated -> {
                    AuthenticatedStartDestination()
                }
                else -> {
                    val context = androidx.compose.ui.platform.LocalContext.current
                    val start = if (OnboardingStore.hasSeenOnboarding(context)) Routes.LOGIN else Routes.ONBOARDING
                    FarketNavGraph(startDestination = start)
                }
            }
        }
    }
}

@Composable
private fun AuthenticatedStartDestination() {
    // Auth'lu bir oturum profilsiz ya da taslak (draft) olabilir (bkz. proje notları):
    // hangi rotaya gidileceğine karar vermeden önce `profiles.status` kontrol edilir.
    // Yok / draft → kurulum sihirbazı (kaldığı yerden), published → ana ekran.
    //
    // Ağ hatası cold-start'ta composition'ı çökertmemeli (uçak modu / zayıf ağ):
    // başarısız çağrı hata ekranına düşer, kullanıcı "Tekrar dene" ile yineler.
    var profileStatus by remember { mutableStateOf<ProfileStatus?>(null) }
    var loadFailed by remember { mutableStateOf(false) }
    var retryTrigger by remember { mutableStateOf(0) }

    LaunchedEffect(retryTrigger) {
        loadFailed = false
        runCatching {
            ProfileRepository(SupabaseClientProvider.client).getProfileStatus()
        }.onSuccess { status ->
            profileStatus = status
        }.onFailure {
            loadFailed = true
        }
    }

    when {
        loadFailed -> StartupErrorScreen(onRetry = { retryTrigger++ })
        profileStatus == null -> LoadingIndicator()
        profileStatus == ProfileStatus.PUBLISHED -> FarketNavGraph(startDestination = Routes.HOME)
        else -> FarketNavGraph(startDestination = Routes.PROFILE_SETUP)
    }
}

@Composable
private fun StartupErrorScreen(onRetry: () -> Unit) {
    val colors = com.farket.app.ui.theme.LocalFarketColors.current
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            androidx.compose.material3.Text(
                text = "Bağlanılamadı. İnternet bağlantını kontrol et.",
                color = colors.textSoft,
            )
            androidx.compose.material3.OutlinedButton(
                onClick = onRetry,
                modifier = Modifier.padding(top = 16.dp),
            ) {
                androidx.compose.material3.Text("Tekrar dene", color = colors.accent)
            }
        }
    }
}

@Composable
private fun LoadingIndicator() {
    val colors = com.farket.app.ui.theme.LocalFarketColors.current
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            // Image (Icon değil) — logo kendi turuncu/siyah renklerini taşıyor,
            // tint uygulanırsa tek renge düzleşir.
            androidx.compose.foundation.Image(
                painter = painterResource(R.drawable.ic_launcher_foreground),
                contentDescription = null,
                modifier = Modifier.size(72.dp).offset(y = (-3).dp),
            )
            CircularProgressIndicator(
                color = colors.accent,
                modifier = Modifier.padding(top = 24.dp).size(20.dp),
                strokeWidth = 2.dp,
            )
        }
    }
}
