package io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.Chain
import io.paritytech.polkadotapp.chains.storage.source.query.AtBlock
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.AirdropEventId
import io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults.AirdropRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainActiveEvent
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropEventInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropPrize
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropStatus
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.MultiLocation
import io.paritytech.polkadotapp.feature_xcm_api.multiLocation.RelativeMultiLocation
import io.paritytech.polkadotapp.test_shared.any
import io.paritytech.polkadotapp.test_shared.whenever
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.mockito.Mockito
import org.mockito.Mockito.mock
import java.math.BigInteger

/**
 * Unit tests for the register-gate logic. Non-airdrop games are always open; an airdrop game stays
 * gated until its event reaches `Registering`; a failed status read stays gated.
 */
class AirdropRegistrationGateTest {
    private val chainRegistry: ChainRegistry = mock()
    private val videoGameRepository: VideoGameRepositoryInternal = mock()
    private val airdropRepository: AirdropRepository = mock()

    private val gate = AirdropRegistrationGate(chainRegistry, videoGameRepository, airdropRepository)

    private val peopleChain: Chain = mock<Chain>().also { whenever(it.id).thenReturn(CHAIN_ID) }

    @Test
    fun `non-airdrop game is always open`() = runBlocking<Unit> {
        stubGame(airdropScheduled = false)

        assertTrue(firstGate())
    }

    @Test
    fun `airdrop game is gated while the event is not registering`() = runBlocking<Unit> {
        stubGame(airdropScheduled = true)
        stubStatus(OnChainAirdropStatus.Scheduled)

        assertFalse(firstGate())
    }

    @Test
    fun `airdrop game opens once the event is registering`() = runBlocking<Unit> {
        stubGame(airdropScheduled = true)
        stubStatus(OnChainAirdropStatus.Registering(totalParticipants = 5))

        assertTrue(firstOpen())
    }

    @Test
    fun `airdrop game stays gated when the status read fails`() = runBlocking<Unit> {
        stubGame(airdropScheduled = true)
        whenever(airdropRepository.subscribeActiveEvent(any(), anyEventId()))
            .thenReturn(flow { throw RuntimeException("rpc down") })

        assertFalse(firstGate())
    }

    // The flow is cold, so it must be built and collected inside the same runBlocking that owns the
    // ComputationalScope (mirrors RealGameResultsInteractorTest).
    private fun firstGate(): Boolean = runBlocking {
        val scope = ComputationalScope(this)
        with(scope) { gate.subscribe() }.first()
    }

    private fun firstOpen(): Boolean = runBlocking {
        val scope = ComputationalScope(this)
        with(scope) { gate.subscribe() }.first { it }
    }

    private fun stubGame(airdropScheduled: Boolean) = runBlocking {
        whenever(chainRegistry.peopleChain()).thenReturn(peopleChain)
        with(any<ComputationalScope>()) {
            whenever(videoGameRepository.subscribeGameInfoAtBlock(any()))
                .thenReturn(flowOf(AtBlock(value = gameInfo(airdropScheduled), at = "0xblock")))
        }
    }

    private fun stubStatus(status: OnChainAirdropStatus) = runBlocking {
        whenever(airdropRepository.subscribeActiveEvent(any(), anyEventId()))
            .thenReturn(flowOf(activeEvent(status)))
    }

    private fun activeEvent(status: OnChainAirdropStatus) = OnChainActiveEvent(
        id = byteArrayOf(1).toDataByteArray(),
        info = OnChainAirdropEventInfo(
            prize = OnChainAirdropPrize(
                assetId = RelativeMultiLocation(parents = 0, interior = MultiLocation.Interior.Here),
                assetAmount = BigInteger.ONE,
                maxWinners = 1,
                winnerCap = 1,
            ),
            registrationStarts = 0L,
            drawTime = 0L,
            endTime = 0L,
        ),
        status = status,
    )

    private fun gameInfo(airdropScheduled: Boolean) = OnChainVideoGameInfo(
        index = GameIndex(1),
        registrationEnds = 0L,
        gameDate = 0L,
        reportEnds = 0L,
        maxGroupSize = 4,
        rounds = 1,
        state = OnChainVideoGameState.PlayerProcess,
        airdropsScheduled = if (airdropScheduled) 1 else 0,
    )

    // AirdropEventId is a value class; a bare any() unboxes to null and NPEs. Register a permissive
    // matcher and return a concrete instance (mirrors test-shared's anyUInt()).
    private fun anyEventId(): AirdropEventId {
        Mockito.argThat<Any?> { true }
        return AirdropEventId.fromGameIndex(GameIndex(0))
    }

    private companion object {
        const val CHAIN_ID = "people-chain-id"
    }
}
