package com.farket.app

import android.app.Application
import com.farket.app.data.SupabaseClientProvider

class FarketApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Supabase client'ı burada, ilk kullanımdan önce başlatılmış olsun diye eager touch ediyoruz.
        SupabaseClientProvider.client
    }
}
