package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.fragment.app.viewModels
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.presentation.screens.BaseComposeFragment
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.compose.TattooFamilyListScreen
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.KnownTokenFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalKnownTokenFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.LocalTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import javax.inject.Inject

@AndroidEntryPoint
class TattooFamilyListFragment : BaseComposeFragment<TattooFamilyListViewModel>() {
    @Inject
    lateinit var amountFormatter: TokenAmountFormatter

    @Inject
    lateinit var tokenFormatter: KnownTokenFormatter

    override val viewModel: TattooFamilyListViewModel by viewModels()

    @Composable
    override fun Screen() {
        CompositionLocalProvider(
            LocalTokenAmountFormatter provides amountFormatter,
            LocalKnownTokenFormatter provides tokenFormatter,
        ) {
            TattooFamilyListScreen(viewModel)
        }
    }
}
