package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.instructions

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import javax.inject.Inject

@HiltViewModel
class EvidencePhotoInstructionsViewModel @Inject constructor(
    private val router: BecomeCitizenRouter,
) : BaseViewModel(), EvidencePhotoInstructionsContract {
    override fun back() {
        router.back()
    }

    override fun openTakePhoto() {
        router.openPhotoCapture()
    }
}
