package com.farket.app.ui.photos

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.farket.app.data.photos.PhotoRow
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.profile.setup.PhotoProcessor
import com.farket.app.ui.theme.LocalFarketColors
import kotlinx.coroutines.launch

/**
 * Fotoğraflarım — bkz. proje notları FARKET_PROMPTLAR.md Prompt 2. Yükleme akışı profil
 * kurulum sihirbazındakiyle (PhotoProcessor + aynı yol biçimi) aynı, burada ayrıca
 * sil/sırala destekleniyor.
 */
@Composable
fun PhotosScreen(
    viewModel: PhotosViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val colors = LocalFarketColors.current
    var isProcessing by remember { mutableStateOf(false) }
    // PickMultipleVisualMedia maxItems > 1 gerektiriyor (aksi halde IllegalArgumentException
    // atıyor) — 6/7 fotoğrafta 1 slot kalınca canlı testte uygulama açılışta çöküyordu.
    val remainingSlots = (7 - uiState.photos.size).coerceAtLeast(2)

    // İşleme ve yükleme bilerek ViewModel'de: burada `rememberCoroutineScope()` kullanmak
    // yüklemeyi sessizce kırıyordu (bkz. PhotosViewModel.addPhotosFromUris).
    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(remainingSlots),
    ) { uris ->
        viewModel.addPhotosFromUris(context.contentResolver, uris)
    }

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        Text("Fotoğraflarım", style = MaterialTheme.typography.headlineSmall)
        Text(
            text = "${uiState.photos.size}/7 (en az 5 gerekli)" +
                if (!uiState.meetsMinimum) " — profilinin yayında kalması için en az 5 gerekiyor" else "",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
        )

        if (uiState.errorMessage != null) {
            Text(
                text = uiState.errorMessage!!,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }

        if (uiState.isLoading) {
            CircularProgressIndicator(color = colors.accent)
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = Modifier.weight(1f, fill = false).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(uiState.photos, key = { it.id }) { photo ->
                    PhotoGridItem(
                        photo = photo,
                        thumbUrl = uiState.thumbUrls[photo.id],
                        onDelete = { viewModel.deletePhoto(photo) },
                        onMoveUp = { viewModel.moveUp(photo) },
                        onMoveDown = { viewModel.moveDown(photo) },
                    )
                }
            }
        }

        if (isProcessing || uiState.isUploading) {
            CircularProgressIndicator(color = colors.accent, modifier = Modifier.padding(top = 12.dp))
        } else if (uiState.canAddMore) {
            OutlinedButton(
                onClick = { launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                shape = RoundedCornerShape(14.dp),
                border = BorderStroke(1.dp, colors.line),
                modifier = Modifier.padding(top = 12.dp),
            ) {
                Text("Fotoğraf ekle")
            }
        }
    }
}

@Composable
private fun PhotoGridItem(
    photo: PhotoRow,
    thumbUrl: String?,
    onDelete: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
) {
    val colors = LocalFarketColors.current

    Column {
        Box(modifier = Modifier.fillMaxWidth().aspectRatio(1f)) {
            if (thumbUrl != null) {
                AsyncImage(
                    model = thumbUrl,
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.Center))
            }
            if (photo.moderationStatus != "approved") {
                Text(
                    text = "onay bekliyor",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(4.dp),
                )
            }
        }
        Box(modifier = Modifier.fillMaxWidth()) {
            IconButton(onClick = onMoveUp, modifier = Modifier.align(Alignment.CenterStart)) {
                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "Yukarı taşı")
            }
            IconButton(onClick = onMoveDown, modifier = Modifier.align(Alignment.Center)) {
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Aşağı taşı")
            }
            IconButton(onClick = onDelete, modifier = Modifier.align(Alignment.CenterEnd)) {
                Icon(Icons.Filled.Delete, contentDescription = "Sil")
            }
        }
    }
}
