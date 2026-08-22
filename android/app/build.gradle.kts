import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// local.properties (git'e girmez) hem debug hem release backend yapılandırmasını taşır:
//   supabase.url               → debug URL (varsayılan: emülatör-yerel 10.0.2.2)
//   supabase.url.release       → Supabase Cloud proje URL'i (https://<ref>.supabase.co)
//   supabase.anon.key.release  → Cloud projesinin anon (public) anahtarı
//   farket.keystore.file/password/alias/aliasPassword → release imzalama
// Release alanları eksikken assembleRelease/bundleRelease AÇIKÇA hata verir —
// localhost URL'in ya da yerel demo anahtarın release APK'ya sessizce gömülmesini önler.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val supabaseUrlDebug = localProperties.getProperty("supabase.url") ?: "http://10.0.2.2:54321"
// Yerel Supabase stack'inin herkese açık demo anon anahtarı — yalnızca debug build'de kullanılır.
val supabaseAnonKeyDebug = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
val supabaseUrlRelease = localProperties.getProperty("supabase.url.release") ?: ""
val supabaseAnonKeyRelease = localProperties.getProperty("supabase.anon.key.release") ?: ""

val keystoreFile = localProperties.getProperty("farket.keystore.file")

android {
    namespace = "com.farket.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.farket.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 3
        versionName = "0.3.0-beta1"
    }

    signingConfigs {
        if (keystoreFile != null) {
            create("release") {
                storeFile = rootProject.file(keystoreFile)
                storePassword = localProperties.getProperty("farket.keystore.password")
                keyAlias = localProperties.getProperty("farket.keystore.alias")
                keyPassword = localProperties.getProperty("farket.keystore.aliasPassword")
            }
        }
    }

    buildTypes {
        debug {
            buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrlDebug\"")
            buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKeyDebug\"")
            // Sabit kodlu beta girişi yalnızca yerel/geliştirme derlemesinde açık.
            buildConfigField("boolean", "BETA_TEST_LOGIN", "true")
        }
        release {
            isMinifyEnabled = false
            buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrlRelease\"")
            buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKeyRelease\"")
            // Herkese açık dağıtımda kapalı: açık kalırsa sabit kodu bilen herkes
            // istediği e-posta adresiyle oturum açabilir (bkz. functions/test-login).
            buildConfigField("boolean", "BETA_TEST_LOGIN", "false")
            if (keystoreFile != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// Release derlemesi, Cloud yapılandırması eksikken sessizce localhost/demo-key
// gömmek yerine anlaşılır bir hatayla dursun.
tasks.configureEach {
    if (name in listOf("assembleRelease", "bundleRelease")) {
        doFirst {
            check(supabaseUrlRelease.startsWith("https://")) {
                "local.properties'te supabase.url.release eksik ya da https değil — release APK üretilemez."
            }
            check(supabaseAnonKeyRelease.isNotBlank()) {
                "local.properties'te supabase.anon.key.release eksik — release APK üretilemez."
            }
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.05.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("androidx.activity:activity-compose:1.9.1")
    implementation("androidx.navigation:navigation-compose:2.7.7")

    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")

    // Supabase Kotlin SDK (BOM ile sürüm yönetimi)
    implementation(platform("io.github.jan-tennert.supabase:bom:3.7.0"))
    implementation("io.github.jan-tennert.supabase:auth-kt")
    implementation("io.github.jan-tennert.supabase:postgrest-kt")
    implementation("io.github.jan-tennert.supabase:storage-kt")
    implementation("io.github.jan-tennert.supabase:realtime-kt")
    implementation("io.github.jan-tennert.supabase:functions-kt")

    // Ktor engine (Supabase SDK bunu gerektirir). ktor-client-android (HttpURLConnection tabanlı)
    // yerine OkHttp motoru kullanılıyor — emülatörde ardışık iki Storage POST isteğinden ikincisi
    // ktor-client-android ile sunucu 200 döndürdüğü halde istemci tarafında süresiz askıda
    // kalıyordu (bkz. ProfileSetupRepository.uploadPhoto yorumu). OkHttp'nin bağlantı havuzu bu
    // senaryoda güvenilir çalışıyor.
    implementation("io.ktor:ktor-client-okhttp:3.5.2")

    implementation("io.coil-kt:coil-compose:2.6.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")
    testImplementation("io.mockk:mockk:1.14.11")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    testImplementation("app.cash.turbine:turbine:1.2.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
