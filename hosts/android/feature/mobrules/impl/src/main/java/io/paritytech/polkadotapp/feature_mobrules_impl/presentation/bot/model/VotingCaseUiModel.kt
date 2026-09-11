package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.bot.model

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsImageRequest
import java.math.BigInteger

@Immutable
sealed interface VotingCaseUiModel {
    val id: BigInteger
    val isSensitive: Boolean

    data class Photo(
        override val id: BigInteger,
        override val isSensitive: Boolean,
        val tattooImage: TattooImage,
        val proofImage: IpfsImageRequest,
        val tattooId: TattooId,
        val tattooFamilyId: DataByteArray
    ) : VotingCaseUiModel

    data class Video(
        override val id: BigInteger,
        override val isSensitive: Boolean,
        val tattooImage: TattooImage,
        val evidenceHash: DataByteArray,
        val proofVideo: IpfsImageRequest,
        val tattooId: TattooId,
        val tattooFamilyId: DataByteArray
    ) : VotingCaseUiModel

    data class Credentials(
        override val id: BigInteger,
        override val isSensitive: Boolean,
        val userProfileLink: String,
        val evidence: String
    ) : VotingCaseUiModel

    data class UsernameValid(
        override val id: BigInteger,
        override val isSensitive: Boolean,
        val username: String,
    ) : VotingCaseUiModel
}
