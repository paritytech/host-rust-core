package io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list

import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.*
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialState
import io.paritytech.polkadotapp.feature_identity_impl.IdentityRouter
import io.paritytech.polkadotapp.feature_identity_impl.domain.interactor.CredentialsListInteractor
import io.paritytech.polkadotapp.feature_identity_impl.presentation.credentials.list.models.CredentialUiModel
import kotlinx.coroutines.flow.SharingStarted
import javax.inject.Inject

class CredentialsListViewModel @Inject constructor(
    private val router: IdentityRouter,
    interactor: CredentialsListInteractor
) : BaseViewModel(), CredentialsListContract {
    override val credentials = interactor.getIdentityCredentialConnectionsFlow()
        .filterResultSuccessNotNull()
        .mapList {
            CredentialUiModel(
                platform = it.platform,
                state = it.state
            )
        }
        .stateInBackground(SharingStarted.Eagerly, emptyList())

    override fun backClicked() {
        router.back()
    }

    override fun selectItem(item: CredentialUiModel) {
        when (item.state) {
            is IdentityCredentialState.Confirmed -> return
            IdentityCredentialState.NotAdded -> router.openAddCredentials(item.platform)
            IdentityCredentialState.Rejected -> router.openCredentialsRejected(item.platform)
            IdentityCredentialState.Review -> router.openCredentialsUnderReview()
        }
    }
}
