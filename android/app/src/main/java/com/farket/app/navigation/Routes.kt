package com.farket.app.navigation

object Routes {
    const val ONBOARDING = "onboarding"
    const val LOGIN = "login"
    const val PROFILE_SETUP = "profile_setup"
    const val HOME = "home"
    const val CITY_SELECTION = "city_selection"
    const val PHOTOS = "photos"

    const val PROFILE_DETAIL_PATTERN = "profile_detail/{profileId}"
    fun profileDetail(profileId: String) = "profile_detail/$profileId"

    const val QUIZ_PATTERN = "quiz/{profileId}"
    fun quiz(profileId: String) = "quiz/$profileId"

    const val IDENTITY_PATTERN = "identity/{attemptId}"
    fun identity(attemptId: String) = "identity/$attemptId"

    const val CONVERSATIONS = "conversations"

    const val CONVERSATION_DETAIL_PATTERN = "conversation/{conversationId}"
    fun conversationDetail(conversationId: String) = "conversation/$conversationId"

    const val NEW_MESSAGE_PATTERN = "new_message/{targetProfileId}/{unlockedTier}"
    fun newMessage(targetProfileId: String, unlockedTier: Int) = "new_message/$targetProfileId/$unlockedTier"

    const val NOTIFICATIONS = "notifications"

    /** Karşılıklı mesajlaşmayla kurulan bağlantılar (bkz. get_my_connections). */
    const val CONNECTIONS = "connections"

    const val ACCOUNT_SETTINGS = "account_settings"
}
