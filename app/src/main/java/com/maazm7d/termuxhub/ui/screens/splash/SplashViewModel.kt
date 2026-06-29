package com.maazm7d.termuxhub.ui.screens.splash

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.maazm7d.termuxhub.domain.usecase.RefreshToolsUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SplashViewModel @Inject constructor(
    private val refreshToolsUseCase: RefreshToolsUseCase
) : ViewModel() {

    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready.asStateFlow()

    init {
        viewModelScope.launch {
            val minDelayMs = 1200L
            val start = System.currentTimeMillis()

            try {
                refreshToolsUseCase()
            } catch (_: Exception) {}

            val elapsed = System.currentTimeMillis() - start
            if (elapsed < minDelayMs) {
                delay(minDelayMs - elapsed)
            }

            _ready.value = true
        }
    }
}
