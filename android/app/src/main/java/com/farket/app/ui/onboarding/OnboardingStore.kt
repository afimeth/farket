package com.farket.app.ui.onboarding

import android.content.Context

private const val PREFS_NAME = "farket_prefs"
private const val KEY_ONBOARDING_SEEN = "onboarding_seen"

/** PaletteStore ile aynı desen — tek bir bayrak için ayrı bir DataStore bağımlılığına değmez. */
object OnboardingStore {
    fun hasSeenOnboarding(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ONBOARDING_SEEN, false)

    fun markSeen(context: Context) {
        prefs(context).edit().putBoolean(KEY_ONBOARDING_SEEN, true).apply()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
