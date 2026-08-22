package com.farket.app.ui

import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.farket.app.data.SupabaseClientProvider
import com.farket.app.data.account.AccountRepository
import com.farket.app.data.auth.EmailAuthRepository
import com.farket.app.data.city.CityRepository
import com.farket.app.data.connections.ConnectionsRepository
import com.farket.app.data.discovery.DiscoveryRepository
import com.farket.app.data.identity.IdentityRepository
import com.farket.app.data.messaging.MessagingRepository
import com.farket.app.data.notifications.NotificationsRepository
import com.farket.app.data.photos.PhotosRepository
import com.farket.app.data.profile.ProfileSetupRepository
import com.farket.app.data.quiz.QuizRepository
import com.farket.app.data.reports.ReportsRepository
import com.farket.app.data.verification.VerificationRepository
import com.farket.app.ui.account.AccountViewModel
import com.farket.app.ui.auth.AuthViewModel
import com.farket.app.ui.city.CityViewModel
import com.farket.app.ui.connections.ConnectionsViewModel
import com.farket.app.ui.discovery.DiscoveryViewModel
import com.farket.app.ui.discovery.ProfileDetailViewModel
import com.farket.app.ui.identity.IdentityViewModel
import com.farket.app.ui.messaging.ConversationDetailViewModel
import com.farket.app.ui.messaging.ConversationListViewModel
import com.farket.app.ui.messaging.NewMessageViewModel
import com.farket.app.ui.notifications.NotificationsViewModel
import com.farket.app.ui.photos.PhotosViewModel
import com.farket.app.ui.profile.setup.ProfileSetupViewModel
import com.farket.app.ui.quiz.QuizViewModel

/**
 * Basit, manuel bir DI: repository'ler tek bir yerde kuruluyor. Proje büyüdükçe Hilt/Koin'e
 * geçmek isterse bu factory'nin yerini alır.
 */
val FarketViewModelFactory = viewModelFactory {
    initializer {
        val authRepository = EmailAuthRepository(SupabaseClientProvider.client)
        AuthViewModel(authRepository)
    }
    initializer {
        val profileSetupRepository = ProfileSetupRepository(SupabaseClientProvider.client)
        ProfileSetupViewModel(profileSetupRepository)
    }
    initializer {
        val cityRepository = CityRepository(SupabaseClientProvider.client)
        CityViewModel(cityRepository)
    }
    initializer {
        val photosRepository = PhotosRepository(SupabaseClientProvider.client)
        PhotosViewModel(photosRepository)
    }
    initializer {
        val discoveryRepository = DiscoveryRepository(SupabaseClientProvider.client)
        DiscoveryViewModel(discoveryRepository)
    }
    initializer {
        val discoveryRepository = DiscoveryRepository(SupabaseClientProvider.client)
        val reportsRepository = ReportsRepository(SupabaseClientProvider.client)
        ProfileDetailViewModel(discoveryRepository, reportsRepository, createSavedStateHandle())
    }
    initializer {
        val quizRepository = QuizRepository(SupabaseClientProvider.client)
        QuizViewModel(quizRepository, createSavedStateHandle())
    }
    initializer {
        val identityRepository = IdentityRepository(SupabaseClientProvider.client)
        IdentityViewModel(identityRepository, createSavedStateHandle())
    }
    initializer {
        val messagingRepository = MessagingRepository(SupabaseClientProvider.client)
        ConversationListViewModel(messagingRepository)
    }
    initializer {
        val messagingRepository = MessagingRepository(SupabaseClientProvider.client)
        val reportsRepository = ReportsRepository(SupabaseClientProvider.client)
        ConversationDetailViewModel(messagingRepository, reportsRepository, SupabaseClientProvider.client, createSavedStateHandle())
    }
    initializer {
        val messagingRepository = MessagingRepository(SupabaseClientProvider.client)
        NewMessageViewModel(messagingRepository, createSavedStateHandle())
    }
    initializer {
        val notificationsRepository = NotificationsRepository(SupabaseClientProvider.client)
        NotificationsViewModel(notificationsRepository)
    }
    initializer {
        val connectionsRepository = ConnectionsRepository(SupabaseClientProvider.client)
        ConnectionsViewModel(connectionsRepository)
    }
    initializer {
        val accountRepository = AccountRepository(SupabaseClientProvider.client)
        val reportsRepository = ReportsRepository(SupabaseClientProvider.client)
        val verificationRepository = VerificationRepository(SupabaseClientProvider.client)
        val profileSetupRepository = ProfileSetupRepository(SupabaseClientProvider.client)
        val quizRepository = QuizRepository(SupabaseClientProvider.client)
        AccountViewModel(accountRepository, reportsRepository, verificationRepository, profileSetupRepository, quizRepository)
    }
}
