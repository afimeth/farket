package com.farket.app.ui.city

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.data.toSafeUserMessage
import com.farket.app.data.city.CityRepository
import com.farket.app.data.city.CityRow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class CityUiState(
    val isLoading: Boolean = true,
    val cities: List<CityRow> = emptyList(),
    val query: String = "",
    val errorMessage: String? = null,
    val citySet: Boolean = false,
) {
    val filteredCities: List<CityRow>
        get() = if (query.isBlank()) cities else cities.filter { it.name.contains(query, ignoreCase = true) }
}

class CityViewModel(
    private val repository: CityRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(CityUiState())
    val uiState: StateFlow<CityUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            runCatching { repository.listCities() }
                .onSuccess { cities -> _uiState.update { it.copy(isLoading = false, cities = cities) } }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isLoading = false, errorMessage = error.toSafeUserMessage("Şehirler yüklenemedi"))
                    }
                }
        }
    }

    fun onQueryChange(query: String) {
        _uiState.update { it.copy(query = query) }
    }

    fun selectCity(cityId: Int) {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            repository.setCity(cityId)
                .onSuccess { _uiState.update { it.copy(isLoading = false, citySet = true) } }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isLoading = false, errorMessage = error.toSafeUserMessage("Şehir değiştirilemedi"))
                    }
                }
        }
    }
}
