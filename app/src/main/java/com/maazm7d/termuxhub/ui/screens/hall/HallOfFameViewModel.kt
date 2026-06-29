package com.maazm7d.termuxhub.ui.screens.hall

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.maazm7d.termuxhub.domain.model.HallOfFameMember
import com.maazm7d.termuxhub.domain.usecase.GetHallOfFameMembersUseCase
import com.maazm7d.termuxhub.domain.usecase.RefreshHallOfFameUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface HallOfFameUiState {
    object Loading : HallOfFameUiState
    data class Success(val members: List<HallOfFameMember>) : HallOfFameUiState
    data class Error(val message: String) : HallOfFameUiState
}

@HiltViewModel
class HallOfFameViewModel @Inject constructor(
    private val getHallOfFameMembersUseCase: GetHallOfFameMembersUseCase,
    private val refreshHallOfFameUseCase: RefreshHallOfFameUseCase
) : ViewModel() {

    private val _uiState = MutableStateFlow<HallOfFameUiState>(HallOfFameUiState.Loading)
    val uiState: StateFlow<HallOfFameUiState> = _uiState.asStateFlow()

    init {
        loadMembers()
    }

    private fun loadMembers() {
    viewModelScope.launch {

        _uiState.value = HallOfFameUiState.Loading

        // Fetch latest data from network
        refreshHallOfFameUseCase()

        // Observe cached database data
        getHallOfFameMembersUseCase().collect { members ->
            _uiState.value = HallOfFameUiState.Success(members)
        }
    }
  }
}
