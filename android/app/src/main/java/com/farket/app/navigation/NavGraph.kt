package com.farket.app.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.farket.app.ui.account.AccountSettingsScreen
import com.farket.app.ui.auth.LoginScreen
import com.farket.app.ui.city.CitySelectionScreen
import com.farket.app.ui.connections.ConnectionsScreen
import com.farket.app.ui.discovery.DiscoveryScreen
import com.farket.app.ui.discovery.ProfileDetailScreen
import com.farket.app.ui.identity.IdentityRevealScreen
import com.farket.app.ui.messaging.ConversationDetailScreen
import com.farket.app.ui.messaging.ConversationListScreen
import com.farket.app.ui.messaging.NewMessageScreen
import com.farket.app.ui.notifications.NotificationsScreen
import com.farket.app.ui.onboarding.OnboardingScreen
import com.farket.app.ui.photos.PhotosScreen
import com.farket.app.ui.profile.setup.ProfileSetupScreen
import com.farket.app.ui.quiz.QuizScreen

@Composable
fun FarketNavGraph(
    navController: NavHostController = rememberNavController(),
    startDestination: String,
) {
    NavHost(navController = navController, startDestination = startDestination) {
        composable(Routes.ONBOARDING) {
            val context = androidx.compose.ui.platform.LocalContext.current
            OnboardingScreen(
                onFinished = {
                    com.farket.app.ui.onboarding.OnboardingStore.markSeen(context)
                    navController.navigate(Routes.LOGIN) {
                        popUpTo(Routes.ONBOARDING) { inclusive = true }
                    }
                },
            )
        }
        composable(Routes.LOGIN) {
            // Giriş linke dokununca deep-link ile tamamlanır; global sessionStatus
            // Authenticated'e döner ve MainActivity/FarketApp bu NavGraph'ı tamamen
            // AuthenticatedStartDestination ile değiştirir (bkz. MainActivity.kt).
            // Bu ekranın kendi başına bir "giriş sonrası" yönlendirmesi yok.
            LoginScreen()
        }
        composable(Routes.PROFILE_SETUP) {
            ProfileSetupScreen(
                onPublished = {
                    navController.navigate(Routes.HOME) {
                        popUpTo(Routes.PROFILE_SETUP) { inclusive = true }
                    }
                },
            )
        }
        composable(Routes.HOME) {
            DiscoveryScreen(
                onOpenCitySelection = { navController.navigate(Routes.CITY_SELECTION) },
                onOpenPhotos = { navController.navigate(Routes.PHOTOS) },
                onOpenConversations = { navController.navigate(Routes.CONVERSATIONS) },
                onOpenNotifications = { navController.navigate(Routes.NOTIFICATIONS) },
                onOpenConnections = { navController.navigate(Routes.CONNECTIONS) },
                onOpenSettings = { navController.navigate(Routes.ACCOUNT_SETTINGS) },
                onOpenProfile = { profileId -> navController.navigate(Routes.profileDetail(profileId)) },
                onStartQuiz = { profileId -> navController.navigate(Routes.quiz(profileId)) },
            )
        }
        composable(Routes.CITY_SELECTION) {
            CitySelectionScreen(onCitySelected = { navController.popBackStack() })
        }
        composable(Routes.PHOTOS) {
            PhotosScreen()
        }
        composable(
            route = Routes.PROFILE_DETAIL_PATTERN,
            arguments = listOf(navArgument("profileId") { type = NavType.StringType }),
        ) {
            ProfileDetailScreen(
                onQuiz = { profileId -> navController.navigate(Routes.quiz(profileId)) },
            )
        }
        composable(
            route = Routes.QUIZ_PATTERN,
            arguments = listOf(navArgument("profileId") { type = NavType.StringType }),
        ) {
            QuizScreen(
                onEliminated = {
                    navController.navigate(Routes.HOME) {
                        popUpTo(Routes.HOME) { inclusive = true }
                    }
                },
                onOpenIdentity = { attemptId -> navController.navigate(Routes.identity(attemptId)) },
                onOpenMessage = { targetProfileId, unlockedTier ->
                    navController.navigate(Routes.newMessage(targetProfileId, unlockedTier))
                },
            )
        }
        composable(
            route = Routes.IDENTITY_PATTERN,
            arguments = listOf(navArgument("attemptId") { type = NavType.StringType }),
        ) {
            IdentityRevealScreen()
        }
        composable(Routes.CONVERSATIONS) {
            ConversationListScreen(
                onOpenConversation = { conversationId -> navController.navigate(Routes.conversationDetail(conversationId)) },
            )
        }
        composable(
            route = Routes.CONVERSATION_DETAIL_PATTERN,
            arguments = listOf(navArgument("conversationId") { type = NavType.StringType }),
        ) {
            ConversationDetailScreen()
        }
        composable(Routes.NOTIFICATIONS) {
            NotificationsScreen(
                onOpenConversations = { navController.navigate(Routes.CONVERSATIONS) },
            )
        }
        composable(Routes.CONNECTIONS) {
            ConnectionsScreen(
                onOpenConversation = { conversationId ->
                    navController.navigate(Routes.conversationDetail(conversationId))
                },
            )
        }
        composable(Routes.ACCOUNT_SETTINGS) {
            AccountSettingsScreen(
                onOpenCitySelection = { navController.navigate(Routes.CITY_SELECTION) },
                onSignedOut = {
                    navController.navigate(Routes.LOGIN) {
                        popUpTo(0) { inclusive = true }
                    }
                },
            )
        }
        composable(
            route = Routes.NEW_MESSAGE_PATTERN,
            arguments = listOf(
                navArgument("targetProfileId") { type = NavType.StringType },
                navArgument("unlockedTier") { type = NavType.IntType },
            ),
        ) {
            NewMessageScreen(
                onSent = { conversationId ->
                    navController.navigate(Routes.conversationDetail(conversationId)) {
                        popUpTo(Routes.HOME)
                    }
                },
            )
        }
    }
}
