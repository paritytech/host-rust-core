package io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.deposit

import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.deposit.model.DepositContent
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.deposit.DepositMessageFormatter
import kotlinx.coroutines.flow.SharingStarted

@HiltViewModel(assistedFactory = DepositAddedMessageViewModel.Factory::class)
class DepositAddedMessageViewModel @AssistedInject constructor(
    @Assisted depositContent: DepositContent,
    depositMessageFormatter: DepositMessageFormatter,
) : BaseViewModel() {
    @AssistedFactory
    interface Factory {
        fun create(depositContent: DepositContent): DepositAddedMessageViewModel
    }

    val depositFormattedAmount = flowOf {
        depositMessageFormatter.formatAmount(depositContent)
    }.stateInBackground(started = SharingStarted.Eagerly, initialValue = null)
}
