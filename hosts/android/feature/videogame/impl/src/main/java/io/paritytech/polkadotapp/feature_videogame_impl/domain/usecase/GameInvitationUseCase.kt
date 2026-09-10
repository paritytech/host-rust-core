package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.feature_people_api.data.storage.InvitationStorage
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.DimName
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssuedInvitation
import io.paritytech.polkadotapp.feature_videogame_api.data.repositories.VideoGameRepository
import io.paritytech.polkadotapp.feature_videogame_impl.domain.invitation.Game
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface GameInvitationUseCase {
    /**
     * Finds locally saved [IssuedInvitation] and validates it against on-chain state
     * So returned non-null value means that this invitation can actually be used during sign up
     */
    fun activeGameInvitationFlow(): Flow<IssuedInvitation?>
}

class RealGameInvitationUseCase @Inject constructor(
    private val invitationStorage: InvitationStorage,
    private val gameRepository: VideoGameRepository,
    private val chainRegistry: ChainRegistry,
) : GameInvitationUseCase {
    override fun activeGameInvitationFlow(): Flow<IssuedInvitation?> {
        return flowOfAll {
            val peopleChain = chainRegistry.peopleChain()

            invitationStorage.subscribeIssuedInvitation(DimName.Game)
                .flatMapLatest { locallySavedInvitation ->
                    if (locallySavedInvitation == null) {
                        return@flatMapLatest flowOf(null)
                    }

                    gameRepository.subscribePendingInvites(
                        peopleChain.id,
                        locallySavedInvitation.inviter,
                        locallySavedInvitation.ticket
                    )
                        .map { hasPendingInvite -> locallySavedInvitation.takeIf { hasPendingInvite } }
                }
        }
    }
}
