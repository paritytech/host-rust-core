package io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.AirdropEventId
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.AirdropRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropStatus
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeGameInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.scan
import timber.log.Timber
import javax.inject.Inject

/**
 * Drives the chat-footer register gate: emits whether registration is open for the active game.
 * Non-airdrop games are always open; an airdrop-scheduled game stays closed until its event reaches
 * the `Registering` phase (via a storage subscription), then latches open for the session — mirroring iOS.
 */
class AirdropRegistrationGate @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val airdropRepository: AirdropRepository,
) {
    context(scope: ComputationalScope)
    fun subscribe(): Flow<Boolean> {
        return flow { emit(chainRegistry.peopleChain().id) }
            .flatMapLatest { chainId -> gateForChain(chainId) }
    }

    context(scope: ComputationalScope)
    private fun gateForChain(chainId: ChainId): Flow<Boolean> {
        return videoGameRepository.subscribeGameInfo(chainId).flatMapLatest { game ->
            if (game?.airdropScheduled != true) {
                flowOf(true)
            } else {
                subscribeGate(chainId, AirdropEventId.fromGameIndex(game.index))
            }
        }
    }

    private fun subscribeGate(chainId: ChainId, eventId: AirdropEventId): Flow<Boolean> {
        return airdropRepository.subscribeActiveEvent(chainId, eventId)
            .map { it?.status is OnChainAirdropStatus.Registering }
            .catch { error ->
                Timber.d(error, "[Airdrop] gate status subscription failed; staying gated")
                emit(false)
            }
            // Latch: once Registering is observed, stay open even if the status later advances.
            .scan(false) { latched, isRegistering -> latched || isRegistering }
            .distinctUntilChanged()
    }
}
