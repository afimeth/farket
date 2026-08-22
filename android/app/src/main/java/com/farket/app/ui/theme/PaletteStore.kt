package com.farket.app.ui.theme

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

private const val PREFS_NAME = "farket_prefs"
private const val KEY_PALETTE = "palette"
private const val KEY_THEME_MODE = "theme_mode"

/**
 * Gündüz/gece tercihi. Renk yönünden (Oda/Fener/Alaca) bağımsızdır: her yönün hem koyu
 * hem açık varyantı var, bu ayar hangisinin kullanılacağını seçer. SYSTEM, cihazın kendi
 * karanlık mod ayarını izler.
 */
enum class FarketThemeMode { SYSTEM, LIGHT, DARK }

/**
 * Bulgu (tasarımcı, düşük öncelik): prototipteki üç renk yönü (Oda/Fener/Alaca) arasında
 * geçiş kontrolü koddaydı ama uygulamada hiç bağlanmamıştı — yalnızca Oda sabitti.
 * Basit bir SharedPreferences deposu: proje henüz DataStore kullanmıyor, iki ayar
 * için yeni bir bağımlılık eklemeye değmez.
 *
 * Aynı durum gündüz/gece için de geçerliydi: paletlerin açık varyantları baştan beri
 * tanımlıydı ama MainActivity temayı `darkTheme = true` ile sabitliyordu, yani açık
 * tema hiç çalışmıyordu.
 */
object PaletteStore {
    private val _palette = MutableStateFlow(FarketPaletteName.ODA)
    val palette: StateFlow<FarketPaletteName> = _palette.asStateFlow()

    private val _themeMode = MutableStateFlow(FarketThemeMode.DARK)
    val themeMode: StateFlow<FarketThemeMode> = _themeMode.asStateFlow()

    fun init(context: Context) {
        val prefs = prefs(context)
        _palette.value = prefs.getString(KEY_PALETTE, null)
            ?.let { runCatching { FarketPaletteName.valueOf(it) }.getOrNull() }
            ?: FarketPaletteName.ODA
        // Varsayılan DARK: uygulamanın bugüne kadarki tek görünümü buydu, mevcut
        // kullanıcılar güncellemeden sonra tema değişmiş gibi hissetmesin.
        _themeMode.value = prefs.getString(KEY_THEME_MODE, null)
            ?.let { runCatching { FarketThemeMode.valueOf(it) }.getOrNull() }
            ?: FarketThemeMode.DARK
    }

    fun set(context: Context, palette: FarketPaletteName) {
        prefs(context).edit().putString(KEY_PALETTE, palette.name).apply()
        _palette.value = palette
    }

    fun setThemeMode(context: Context, mode: FarketThemeMode) {
        prefs(context).edit().putString(KEY_THEME_MODE, mode.name).apply()
        _themeMode.value = mode
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
