package com.farket.app.ui.city

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.theme.LocalFarketColors

/**
 * Şehir seçimi — bkz. proje notları FARKET_PROMPTLAR.md Prompt 1. `set_city` RPC'si 24 saat
 * kuralına tabi (bkz. CityRepository), hata mesajı olduğu gibi kullanıcıya gösteriliyor.
 */
@Composable
fun CitySelectionScreen(
    onCitySelected: () -> Unit,
    viewModel: CityViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()

    LaunchedEffect(uiState.citySet) {
        if (uiState.citySet) {
            onCitySelected()
        }
    }

    val colors = LocalFarketColors.current

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        Text("Şehir seç", style = MaterialTheme.typography.headlineSmall)

        OutlinedTextField(
            value = uiState.query,
            onValueChange = viewModel::onQueryChange,
            label = { Text("Ara") },
            shape = RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = colors.accent,
                unfocusedBorderColor = colors.line,
                focusedLabelColor = colors.accent,
            ),
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 8.dp),
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
            LazyColumn {
                items(uiState.filteredCities, key = { it.id }) { city ->
                    ListItem(
                        headlineContent = { Text(city.name) },
                        modifier = Modifier.clickable { viewModel.selectCity(city.id) },
                    )
                    HorizontalDivider(color = colors.line)
                }
            }
        }
    }
}
