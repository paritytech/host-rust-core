package io.paritytech.polkadotapp.app.root.navigation.becomeCitizen

import io.paritytech.polkadotapp.app.R
import io.paritytech.polkadotapp.app.root.navigation.BaseNavigator
import io.paritytech.polkadotapp.app.root.navigation.NavigationHolder
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.utils.toPayloadBundle
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.toParcelable
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.familydetails.TattooFamilyDetailsPayload
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.TattooDetailsPayload
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import jakarta.inject.Inject

class BecomeCitizenNavigator @Inject constructor(
    navigationHolder: NavigationHolder,
) : BaseNavigator(navigationHolder), BecomeCitizenRouter {
    override fun openSelectAndReserveTattoo() = performNavigation(
        R.id.action_global_to_commit_to_tattoo_graph
    )

    override fun openProvideVideoEvidence() {
        performNavigation(R.id.action_global_to_evidence_video_graph)
    }

    override fun openProvidePhotoEvidence() {
        performNavigation(R.id.action_global_to_evidence_photo_graph)
    }

    override fun openTattooFamilyDetails(payload: TattooFamilyDetailsPayload) {
        performNavigation(
            actionId = R.id.action_tattooFamilyListFragment_to_tattooFamilyDetailsFragment,
            args = payload.toPayloadBundle()
        )
    }

    override fun openTattooDetails(tattooId: TattooId, familyId: DataByteArray) {
        val payload = TattooDetailsPayload(
            tattooId = tattooId.toParcelable(),
            familyId = familyId.value
        )

        performNavigation(
            actionId = R.id.action_tattooFamilyDetailsFragment_to_tattooDetailsFragment,
            args = payload.toPayloadBundle()
        )
    }

    override fun popTattooSelection() {
        popBackstack(destinationId = R.id.commit_to_tattoo_graph, inclusive = true)
    }

    override fun openVideoRecorder() {
        performNavigation(R.id.action_evidenceVideoInstructionsFragment_to_videoRecordFragment)
    }

    override fun openVideoPreview() {
        performNavigation(R.id.action_videoRecordFragment_to_evidenceVideoPreviewFragment)
    }

    override fun popEvidenceVideo() {
        popBackstack(destinationId = R.id.evidence_video_graph, inclusive = true)
    }

    override fun openPhotoCapture() {
        performNavigation(R.id.action_evidencePhotoInstructionsFragment_to_evidencePhotoCaptureFragment)
    }

    override fun openPhotoPreview() {
        performNavigation(R.id.action_evidencePhotoCaptureFragment_to_evidencePhotoPreviewFragment)
    }

    override fun popEvidencePhoto() {
        popBackstack(destinationId = R.id.evidence_photo_graph, inclusive = true)
    }

    override fun openUpgradeUsername() {
        performNavigation(R.id.action_global_to_upgradeUsernameFragment)
    }

    override fun openChatFeed(payload: ChatFeedPayload) {
        performNavigation(
            actionId = R.id.action_global_to_chatFeedFragment,
            args = payload.toPayloadBundle()
        )
    }
}
