package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.presentation.navigation.ReturnableRouter
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.TattooFamilyDetailsPayload
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload

interface BecomeCitizenRouter : ReturnableRouter {
    fun openSelectAndReserveTattoo()
    fun openProvideVideoEvidence()
    fun openProvidePhotoEvidence()

    fun openTattooFamilyDetails(payload: TattooFamilyDetailsPayload)
    fun openTattooDetails(tattooId: TattooId, familyId: DataByteArray)
    fun popTattooSelection()

    fun openVideoRecorder()
    fun openVideoPreview()
    fun popEvidenceVideo()

    fun openPhotoCapture()
    fun openPhotoPreview()
    fun popEvidencePhoto()

    fun openUpgradeUsername()
    fun openChatFeed(payload: ChatFeedPayload)
}
