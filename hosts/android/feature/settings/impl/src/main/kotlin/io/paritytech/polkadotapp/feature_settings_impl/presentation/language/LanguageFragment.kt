package io.paritytech.polkadotapp.feature_settings_impl.presentation.language

import androidx.compose.runtime.Composable
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_settings_impl.presentation.language.compose.LanguageScreen

@AndroidEntryPoint
class LanguageFragment : BaseComposeFragment<LanguageViewModel>() {
    override val viewModel: LanguageViewModel by viewModels()

    @Composable
    override fun Screen() {
        LanguageScreen(contract = viewModel)
    }
}
