package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list

import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.models.CredentialUiModel
import kotlinx.coroutines.flow.StateFlow

interface CredentialsListContract {
    val credentials: StateFlow<List<CredentialUiModel>>

    fun backClicked()

    fun selectItem(item: CredentialUiModel)
}
