package com.farket.app.data

import com.farket.app.BuildConfig
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import io.github.jan.supabase.storage.Storage

/**
 * Tek bir SupabaseClient örneği tüm uygulama boyunca paylaşılır (repository'ler bunu enjekte eder).
 */
object SupabaseClientProvider {

    val client by lazy {
        createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_ANON_KEY,
        ) {
            install(Auth) {
                // Link-tabanlı e-posta girişi: Cloud ücretsiz plan e-posta şablonunu
                // özelleştirmeye izin vermediği için (kod görünmüyor), kullanıcı
                // e-postadaki linke dokunuyor, uygulama bu deep-link ile açılıp
                // oturumu tamamlıyor (bkz. MainActivity.handleAuthDeeplink).
                host = "login-callback"
                scheme = "farket"
            }
            install(Postgrest)
            install(Storage)
            install(Realtime)
            install(Functions)
        }
    }
}
