package com.farket.app.ui.discovery

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBox
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.layout.ContentScale
import coil.compose.AsyncImage
import com.farket.app.data.discovery.DiscoverProfileRow
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.common.EmptyState
import com.farket.app.ui.theme.LocalFarketColors
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Keşif ekranı — ana ekran. Bkz. proje notları FARKET_PROMPTLAR.md Prompt 4.
 * "Şehir Değiştir"/"Fotoğraflarım" butonları, ayarlar ekranı (Prompt 9) yazılana kadar
 * geçici erişim noktaları.
 */
@Composable
fun DiscoveryScreen(
    onOpenCitySelection: () -> Unit,
    onOpenPhotos: () -> Unit,
    onOpenConversations: () -> Unit,
    onOpenNotifications: () -> Unit,
    onOpenConnections: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenProfile: (profileId: String) -> Unit,
    onStartQuiz: (profileId: String) -> Unit,
    viewModel: DiscoveryViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalFarketColors.current
    var showFullDeck by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 20.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(text = "Keşfet", style = MaterialTheme.typography.headlineSmall)
            if (uiState.cards.isNotEmpty()) {
                TextButton(onClick = { showFullDeck = !showFullDeck }) {
                    Text(
                        if (showFullDeck) "Kart görünümü" else "Tüm desteyi gör",
                        color = colors.accent,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
        // Üst bar tümüyle ikon ve satırın tamamına yayılıyor: her düğme eşit paya
        // sahip (weight). Başlıkla bar arası 5dp, ikon araları en az 2dp (3dp) —
        // gölge yayılımı arayı görsel olarak kapatmasın diye gölge dar tutuluyor.
        Row(
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            modifier = Modifier.fillMaxWidth().padding(top = 5.dp, bottom = 16.dp),
        ) {
            TopBarIconButton(Icons.Filled.Notifications, "Bildirimler", onOpenNotifications, Modifier.weight(1f))
            TopBarIconButton(Icons.Filled.MailOutline, "Mesajlar", onOpenConversations, Modifier.weight(1f))
            TopBarIconButton(Icons.Filled.Favorite, "Bağlantılarım", onOpenConnections, Modifier.weight(1f))
            TopBarIconButton(Icons.Filled.AccountBox, "Fotoğraflarım", onOpenPhotos, Modifier.weight(1f))
            TopBarIconButton(Icons.Filled.LocationOn, "Şehir değiştir", onOpenCitySelection, Modifier.weight(1f))
            TopBarIconButton(Icons.Filled.Settings, "Ayarlar", onOpenSettings, Modifier.weight(1f))
        }

        // Günlük deste sınırı bir hata değil, günün doğal sonu. Ham hata metni +
        // işe yaramayacak bir "Tekrar dene" yerine kullanıcıyı yapabileceği bir şeye
        // yönlendiriyoruz — döngünün çıkışsız olmaması gerekiyor.
        val deckExhausted = uiState.errorMessage?.contains("deste sınırına") == true

        if (uiState.errorMessage != null && !deckExhausted) {
            Text(
                text = uiState.errorMessage!!,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }

        if (uiState.isLoading && uiState.cards.isEmpty()) {
            CircularProgressIndicator(color = colors.accent)
        } else if (uiState.cards.isEmpty() && deckExhausted) {
            EmptyState("Bugünlük keşif bitti.")
            Text(
                "Yarın yeni profiller gelecek. Bu arada kendi profilini güçlendirebilirsin: " +
                    "eksik maddeleri tamamlarsan yarınki quiz hakkın artar.",
                style = MaterialTheme.typography.bodySmall,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 8.dp),
            )
            Button(
                onClick = onOpenSettings,
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
                modifier = Modifier.padding(top = 12.dp),
            ) {
                Text("Günlük hakkıma bak")
            }
        } else if (uiState.cards.isEmpty()) {
            EmptyState("Şu an gösterecek yeni biri yok.")
            OutlinedButton(
                onClick = viewModel::loadMore,
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, colors.line),
                modifier = Modifier.padding(top = 12.dp),
            ) {
                Text("Tekrar dene")
            }
        } else if (showFullDeck) {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                items(uiState.cards, key = { it.id }) { card ->
                    DiscoveryCard(
                        card = card,
                        coverUrl = uiState.coverUrls[card.id],
                        onSkip = { viewModel.skip(card) },
                        onClick = { onOpenProfile(card.id) },
                    )
                }
            }
        } else {
            val card = uiState.cards.first()
            DiscoveryPagerCard(
                card = card,
                coverUrl = uiState.coverUrls[card.id],
                photoUrls = uiState.photoUrls[card.id].orEmpty(),
                onSkip = { viewModel.skip(card) },
                onOpenProfile = { onOpenProfile(card.id) },
                onStartQuiz = { onStartQuiz(card.id) },
            )
        }
    }
}

/**
 * Üst bardaki orta boy ikon düğmesi.
 *
 * Arka plan sayfa zemininden ayrışsın diye `surface` + ince `line` kenarlığı kullanıyor.
 * Gölge iki katman: geniş ve yumuşak bir ortam gölgesi (nesnenin çevresine yayılan dolaylı
 * ışık) ile dar ve koyu bir ana gölge (doğrudan ışık). Compose gerçek ışın izleme yapamaz;
 * bu iki katman, tek düz gölgeye göre çok daha inandırıcı bir derinlik veriyor. Ortam
 * gölgesine hafif accent tonu katıldı — yüzeyden sekmiş renkli ışığın karşılığı.
 */
@Composable
private fun TopBarIconButton(
    icon: ImageVector,
    description: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalFarketColors.current
    val shape = RoundedCornerShape(14.dp)

    Box(
        modifier = modifier
            .height(50.dp)
            .shadow(
                elevation = 8.dp,
                shape = shape,
                ambientColor = colors.accent.copy(alpha = 0.35f),
                spotColor = Color.Black,
            )
            .shadow(
                elevation = 2.dp,
                shape = shape,
                ambientColor = Color.Black,
                spotColor = Color.Black,
            )
            .clip(shape)
            .background(colors.surface)
            .border(1.dp, colors.line, shape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = description,
            tint = colors.textSoft,
            modifier = Modifier.size(23.dp),
        )
    }
}

// Kartı bu kadar dikey sürükleyince jest tamamlanmış sayılır (yanlışlıkla ufak
// kaydırmalarda tetiklenmemesi için).
private val DRAG_COMMIT_THRESHOLD_DP = 140.dp

@Composable
private fun DiscoveryPagerCard(
    card: DiscoverProfileRow,
    coverUrl: String?,
    photoUrls: List<String>,
    onSkip: () -> Unit,
    onOpenProfile: () -> Unit,
    onStartQuiz: () -> Unit,
) {
    val colors = LocalFarketColors.current
    val density = LocalDensity.current
    val thresholdPx = with(density) { DRAG_COMMIT_THRESHOLD_DP.toPx() }
    val coroutineScope = rememberCoroutineScope()

    // photoUrls henüz imzalanmadıysa (ilk render) tek kapak fotoğrafına düş.
    val pages = photoUrls.ifEmpty { listOfNotNull(coverUrl) }
    val photoPagerState = rememberPagerState(pageCount = { pages.size.coerceAtLeast(1) })

    val offsetY = remember(card.id) { Animatable(0f) }
    var showQuizConfirm by remember(card.id) { mutableStateOf(false) }

    if (showQuizConfirm) {
        // Maliyet taahhütten ÖNCE yazılıyor: eskiden burada yalnızca "emin misin?"
        // vardı, kullanıcı 5. soruda elenince profilin 3 gün gizleneceğini ve profil
        // başına yalnızca iki deneme hakkı olduğunu ancak olan olduktan sonra
        // öğreniyordu. Ne kaybedeceğini bilmeden verilen onay, onay değil.
        AlertDialog(
            onDismissRequest = { showQuizConfirm = false },
            title = { Text("Quiz'e başla") },
            text = {
                Text(
                    "@${card.username} için 10 soruluk quiz başlayacak.\n\n" +
                        "• 5. soruda ara kontrol var: en az 4 doğru gerekiyor.\n" +
                        "• Geçemezsen bu profil 3 gün gizlenir.\n" +
                        "• 7 doğru mesaj hakkı açar; 8'de fotoğrafına değinebilir, " +
                        "9'da gizli kartı görür ve soru sorabilir, 10'da mühür kazanırsın.\n" +
                        "• Bu profil için toplam 2 deneme hakkın var, bu birincisi.\n" +
                        "• Günlük quiz hakkından 1 düşer.",
                )
            },
            confirmButton = {
                TextButton(onClick = { showQuizConfirm = false; onStartQuiz() }) { Text("Başla") }
            },
            dismissButton = { TextButton(onClick = { showQuizConfirm = false }) { Text("Vazgeç") } },
        )
    }

    Card(
        modifier = Modifier
            .fillMaxSize()
            .padding(vertical = 4.dp)
            .offset { IntOffset(0, offsetY.value.roundToInt()) }
            .pointerInput(card.id) {
                detectVerticalDragGestures(
                    onVerticalDrag = { change, dragAmount ->
                        change.consume()
                        coroutineScope.launch { offsetY.snapTo(offsetY.value + dragAmount) }
                    },
                    onDragEnd = {
                        val current = offsetY.value
                        when {
                            current <= -thresholdPx -> {
                                coroutineScope.launch { offsetY.animateTo(0f) }
                                showQuizConfirm = true
                            }
                            current >= thresholdPx -> onSkip()
                            else -> coroutineScope.launch { offsetY.animateTo(0f) }
                        }
                    },
                )
            },
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        border = BorderStroke(1.dp, colors.line),
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            if (pages.isNotEmpty()) {
                HorizontalPager(
                    state = photoPagerState,
                    modifier = Modifier.fillMaxSize(),
                    userScrollEnabled = false,
                ) { photoPage ->
                    AsyncImage(
                        model = pages[photoPage],
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .pointerInput(pages.size) {
                            detectTapGestures(
                                onTap = { offset ->
                                    when {
                                        offset.x < size.width * 0.25f -> coroutineScope.launch {
                                            photoPagerState.animateScrollToPage(
                                                (photoPagerState.currentPage - 1).coerceAtLeast(0),
                                            )
                                        }
                                        offset.x > size.width * 0.75f -> coroutineScope.launch {
                                            photoPagerState.animateScrollToPage(
                                                (photoPagerState.currentPage + 1).coerceAtMost(pages.lastIndex),
                                            )
                                        }
                                        else -> onOpenProfile()
                                    }
                                },
                            )
                        },
                )
            } else {
                CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.Center))
            }
            if (pages.size > 1) {
                Row(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 12.dp)
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    pages.indices.forEach { dotIndex ->
                        val isActive = dotIndex == photoPagerState.currentPage
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(3.dp)
                                .background(
                                    color = Color.White.copy(alpha = if (isActive) 0.9f else 0.35f),
                                    shape = RoundedCornerShape(2.dp),
                                ),
                        )
                    }
                }
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f)),
                        ),
                    )
                    .padding(20.dp),
            ) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("@${card.username}", style = MaterialTheme.typography.headlineSmall, color = Color.White)
                        if (card.isBot) {
                            Box(
                                modifier = Modifier
                                    .padding(start = 8.dp)
                                    .background(Color.White.copy(alpha = 0.25f), shape = RoundedCornerShape(6.dp))
                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                            ) {
                                Text(
                                    "Testbotu",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = Color.White,
                                )
                            }
                        }
                    }
                    // "Atla"/"Quizle" düğmeleri kaldırıldı: aynı iki eylem zaten yukarı/
                    // aşağı kaydırmayla yapılıyordu ve düğmeler fotoğrafın üzerini
                    // kapatıyordu. Jest, girişte (OnboardingScreen) kullanıcıya
                    // gösterilip anladığı teyit ediliyor.
                }
            }
        }
    }
}

@Composable
private fun DiscoveryCard(
    card: DiscoverProfileRow,
    coverUrl: String?,
    onSkip: () -> Unit,
    onClick: () -> Unit,
) {
    val colors = LocalFarketColors.current

    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        border = BorderStroke(1.dp, colors.line),
    ) {
        Column {
            Box(modifier = Modifier.fillMaxWidth().aspectRatio(1f)) {
                if (coverUrl != null) {
                    AsyncImage(
                        model = coverUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.Center))
                }
            }
            Column(modifier = Modifier.padding(14.dp)) {
                Text("@${card.username}", style = MaterialTheme.typography.titleMedium)
                if (card.solveRate != null) {
                    Text(
                        "%${card.solveRate} çözülme",
                        style = MaterialTheme.typography.labelMedium,
                        color = colors.textFaint,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
                Row(modifier = Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = onSkip,
                        shape = RoundedCornerShape(12.dp),
                        border = BorderStroke(1.dp, colors.line),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.textSoft),
                    ) { Text("Atla") }
                    Button(
                        onClick = onClick,
                        shape = RoundedCornerShape(12.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
                    ) { Text("Quizle") }
                }
            }
        }
    }
}
