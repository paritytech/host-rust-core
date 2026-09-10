package io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.harness

import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.paritytech.polkadotapp.chains.extrinsic.ExtrinsicStatus
import io.paritytech.polkadotapp.chains.multiNetwork.connection.ChainConnectionRefCounter
import io.paritytech.polkadotapp.chains.multiNetwork.connection.EnabledChainConnectionReference
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.model.CoinageTransactionId
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.context.RealCoinageSigningContextProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainViewFactory
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.RealCoinageTransactionService
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.CoinageEvidenceCollector
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.CoinageRecoveryLoop
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.CoinageRecoveryScheduler
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.RealCoinageRecoveryPass
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.registration.CoinageEntryRegistrar
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.submission.CoinageSubmissionTracker
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.submission.SubmissionOwnedEntries
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_transactions.api.data.ExtrinsicService
import io.paritytech.polkadotapp.test_shared.TestCoroutineDispatchers
import io.paritytech.polkadotapp.test_shared.chain.FakeChain
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle

/**
 * The whole subsystem over a [FakeChain] and an in-memory ledger, on one [TestScope].
 *
 * [crash] is the point of the harness: it cancels every watcher and pass, drops every volatile set, and
 * builds the subsystem again over the same store — which is only possible because no volatile state is
 * global. Uncommitted handoff marks go with it, the way a relaunch releases them.
 */
class DurabilityHarness(
    private val testScope: TestScope,
    initialState: CoinageChainState,
) {
    val chain = FakeCoinageChainViewFactory(FakeChain(initialState))
    val repository = InMemoryCoinageEntryRepository()

    /** References the tracker holds, so a scenario can assert a watch keeps the chain connected. */
    val connections = RecordingConnectionRefCounter()

    val coinDerivation = FakeCoinKeypairDerivation()
    val voucherDerivation = FakeVoucherRingDerivation()

    /** Statuses the watcher sees for the n-th submission; an empty flow leaves it to the silence timeout. */
    var submissionStatuses: (Int) -> Flow<ExtrinsicStatus> = { emptyFlow() }

    private var submissions = 0
    private var extrinsics = 0
    private var subsystem = launchSubsystem()

    /** How many extrinsics the tracker has subscribed to, so a scenario can assert no resubmission followed. */
    val submissionCount: Int get() = submissions

    val service: RealCoinageTransactionService get() = subsystem.service
    val ownedEntries: SubmissionOwnedEntries get() = subsystem.ownedEntries
    val recoveryPass: RealCoinageRecoveryPass get() = subsystem.pass

    internal fun nextExtrinsicHex(): String = "0x" + (extrinsics++).toString(16).padStart(8, '0')

    /** Recovery being asked for is the observable half of a submission release; running it is [runPass]. */
    fun assertRecoveryWasRequested() {
        check(subsystem.scheduler.requests > 0) { "expected a recovery request, but none was made" }
    }

    /**
     * The other half: an entry the watcher decided needs no pass, and asking for one is pure cost — a worker
     * scheduled and a chain view pinned to look at transactions that are already settled.
     */
    fun assertRecoveryWasNotRequested() {
        check(subsystem.scheduler.requests == 0) {
            "expected no recovery request, but ${subsystem.scheduler.requests} were made"
        }
    }

    fun crash() {
        subsystem.close()
        subsystem = launchSubsystem()
    }

    /** What a relaunch does before anything else, so a scenario can model process start rather than a crash. */
    suspend fun relaunch() {
        crash()
        service.releaseUncommittedHandoffs()
    }

    fun advanceBlocks(count: Int, finality: TestActionFinality) {
        repeat(count) { chain.produceBlock() }
        if (finality == TestActionFinality.FINALIZED) finalizeToBest()
    }

    fun finalizeToBest() = chain.finalize(chain.chain.bestHead.number)

    /**
     * Advances the best head past [id]'s mortality end, and the finalized head with it when asked.
     *
     * `windowClosed` reads the finalized head, so only FINALIZED actually expires the window; IN_BEST is the
     * finality-stall case, where height alone must decide nothing. Read from the entry rather than assuming
     * the registrar's constant, so this keeps working if the window changes.
     *
     * FINALIZED finalizes every block below the best head, not only the ones it produced. There is one
     * finalized head, so that is unavoidable — but the caller wrote FINALIZED, so it is a stated choice.
     */
    suspend fun chainReachesMortalityOf(id: CoinageTransactionId, finality: TestActionFinality) {
        val entry = repository.getEntry(id).getOrThrow() ?: error("no entry ${id.value}")
        val target = entry.mortalityEnd + 1

        while (chain.chain.bestHead.number < target) chain.produceBlock()
        if (finality == TestActionFinality.FINALIZED) finalizeToBest()
    }

    suspend fun runPass() = recoveryPass.run().getOrThrow()

    /**
     * Runs the watchers to their release. A pass skips exactly the entries submission still owns, so a
     * scenario that wants the pass to decide has to get past this first.
     */
    fun releaseSubmissions() = testScope.advanceUntilIdle()

    private fun launchSubsystem(): Subsystem {
        val dispatcher = StandardTestDispatcher(testScope.testScheduler)
        val scope = CoroutineScope(testScope.coroutineContext + SupervisorJob())
        val ownedEntries = SubmissionOwnedEntries()

        val registrar = CoinageEntryRegistrar(
            repository = repository,
            coinKeypairDerivation = coinDerivation,
            voucherRingDerivation = voucherDerivation,
            submissionOwnedEntries = ownedEntries,
        )

        val pass = RealCoinageRecoveryPass(
            repository = repository,
            chainViewFactory = chain,
            evidenceCollector = CoinageEvidenceCollector(
                voucherRingDerivation = voucherDerivation,
                coinageSigningContextProvider = RealCoinageSigningContextProvider(),
            ),
            submissionOwnedEntries = ownedEntries,
        )

        val loop = CoinageRecoveryLoop(repository = repository, recoveryPass = pass, chainViewFactory = chain)
        val scheduler = RecordingRecoveryScheduler()

        val service = RealCoinageTransactionService(
            registrar = registrar,
            submissionTracker = submissionTracker(ownedEntries, chain),
            recoveryLoop = loop,
            recoveryScheduler = scheduler,
            repository = repository,
            dispatchers = TestCoroutineDispatchers(dispatcher),
        )

        return Subsystem(service, ownedEntries, pass, scheduler, scope)
    }

    private fun submissionTracker(
        ownedEntries: SubmissionOwnedEntries,
        chainViewFactory: CoinageChainViewFactory,
    ): CoinageSubmissionTracker {
        val chainAssetProvider: ChainAssetProvider = mockk()
        val extrinsicService: ExtrinsicService = mockk()

        coEvery { chainAssetProvider.chain() } returns mockk(relaxed = true)
        every { extrinsicService.submitAndWatchBuiltExtrinsic(any(), any(), any()) } answers {
            submissionStatuses(submissions++)
        }

        return CoinageSubmissionTracker(
            chainAssetProvider = chainAssetProvider,
            extrinsicService = extrinsicService,
            repository = repository,
            chainViewFactory = chainViewFactory,
            submissionOwnedEntries = ownedEntries,
            resubmitWhenValidFactory = mockk(relaxed = true),
            chainConnectionRefCounter = connections,
        )
    }

    private class Subsystem(
        val service: RealCoinageTransactionService,
        val ownedEntries: SubmissionOwnedEntries,
        val pass: RealCoinageRecoveryPass,
        val scheduler: RecordingRecoveryScheduler,
        private val scope: CoroutineScope,
    ) {
        fun close() {
            service.close()
            scope.cancel()
        }
    }
}

/**
 * Records the request instead of launching the loop, so `runPass()` is the only thing that runs a pass.
 *
 * Production starts the loop here, and the loop wakes on every head emission — which in a harness means
 * every block a scenario produces queues a background pass whose timing decides the outcome. The loop is
 * covered on its own by `CoinageRecoveryLoopTest`; what these scenarios test is the pass.
 */
private class RecordingRecoveryScheduler : CoinageRecoveryScheduler {
    var requests = 0
        private set

    override fun ensureRunning() {
        requests++
    }
}

/** Blocks a coinage extrinsic stays valid for in the harness, matching what the chain would build. */
const val HARNESS_MORTAL_PERIOD = 128

/**
 * An extrinsic whose `CheckMortality` era is anchored at the chain's current finalized head, which is what
 * the registrar reads its window from.
 */

/**
 * An extrinsic whose `CheckMortality` era is anchored at the chain's current finalized head.
 *
 * Its bytes are generated rather than passed in. They only have to be *distinct* — the body search looks an
 * entry's txHash up in block bodies, so two entries sharing bytes would find each other's blocks — and a
 * value a test has to invent but never reads is noise. A scenario that needs the hash reads it back off the
 * entry.
 */
fun DurabilityHarness.extrinsicAnchoredAtFinalizedHead(periodBlocks: Int = HARNESS_MORTAL_PERIOD) =
    extrinsicAnchoredAt(chain.chain.finalizedHead.number, periodBlocks)

/** An era anchored somewhere other than the current head, so a scenario can put the two in different periods. */
fun DurabilityHarness.extrinsicAnchoredAt(block: Long, periodBlocks: Int = HARNESS_MORTAL_PERIOD) =
    mortalExtrinsic(
        hex = nextExtrinsicHex(),
        anchorBlock = block,
        periodBlocks = periodBlocks,
        anchorHash = chain.chain.canonicalAt(block)?.hash ?: error("no canonical block at $block"),
    )

/** No mortal era at all, so the registrar has no window to anchor to. */
fun DurabilityHarness.immortalExtrinsic() = immortalExtrinsic(nextExtrinsicHex())

/**
 * Counts outstanding references rather than enabling anything: what a scenario needs to know is whether the
 * watch is holding the connection open, and whether it let go when it finished.
 */
class RecordingConnectionRefCounter : ChainConnectionRefCounter {
    var held = 0
        private set

    /** The most references outstanding at once — a watch that has already finished still shows up here. */
    var peak = 0
        private set

    override fun shouldConnectionBeEnabled(chainId: String): Flow<Boolean> = flowOf(held > 0)

    override suspend fun requestConnectionEnabled(
        chainIds: Set<String>,
        label: String,
    ): EnabledChainConnectionReference {
        held++
        peak = maxOf(peak, held)

        return object : EnabledChainConnectionReference {
            override suspend fun release() {
                held--
            }
        }
    }
}
