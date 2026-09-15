package io.paritytech.polkadotapp.feature_coinage_impl.domain.service

import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchPublicKey
import io.paritytech.polkadotapp.bandersnatch_crypto.aliasInContext
import io.paritytech.polkadotapp.chains.storage.source.query.api.StorageKey4
import io.paritytech.polkadotapp.common.data.cache.CacheableDataConsistency
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.filterNotNull
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.common.utils.measureExecution
import io.paritytech.polkadotapp.feature_account_api.data.storage.newaccount.NewAccountStorage
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.BackupProgress
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin.Age
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher.Location
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.toRingCollectionId
import io.paritytech.polkadotapp.feature_coinage_api.domain.service.CoinageBackupService
import io.paritytech.polkadotapp.feature_coinage_impl.data.config.CoinageInstanceIdProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.CoinKeypairDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.VoucherRingDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.getDerivedAccountIds
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.getDerivedMemberKeys
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainAliasState
import io.paritytech.polkadotapp.feature_coinage_impl.data.model.OnChainCoinInfo
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.CoinRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.VoucherRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.context.CoinageSigningContextProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.CoinsBackupLastIndexStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.CoinsDeepBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.CoinsInitialBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.VouchersBackupLastIndexStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.VouchersDeepBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.VouchersInitialBackupCompletedStorage
import io.paritytech.polkadotapp.feature_members_api.data.model.RingPosition
import io.paritytech.polkadotapp.feature_members_api.data.repository.MembersRepository
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

class RealCoinageBackupService @Inject constructor(
    @param:DigitalDollarChainAssetProvider private val chainAssetProvider: ChainAssetProvider,
    private val coinsInitialBackupCompletedStorage: CoinsInitialBackupCompletedStorage,
    private val vouchersInitialBackupCompletedStorage: VouchersInitialBackupCompletedStorage,
    private val coinsDeepBackupCompletedStorage: CoinsDeepBackupCompletedStorage,
    private val vouchersDeepBackupCompletedStorage: VouchersDeepBackupCompletedStorage,
    private val coinsBackupLastIndexStorage: CoinsBackupLastIndexStorage,
    private val vouchersBackupLastIndexStorage: VouchersBackupLastIndexStorage,
    private val newAccountStorage: NewAccountStorage,
    private val coinsRepository: CoinRepository,
    private val voucherRepository: VoucherRepository,
    private val membersRepository: MembersRepository,
    private val keypairDerivation: CoinKeypairDerivation,
    private val voucherRingDerivation: VoucherRingDerivation,
    private val coinageSigningContextProvider: CoinageSigningContextProvider,
    private val coinageInstanceIdProvider: CoinageInstanceIdProvider,
) : CoinageBackupService {
    companion object {
        private const val BATCH_SIZE = 500
        private const val EMPTY_BATCH_COUNT = 4

        private const val DEEP_SEARCH_BATCH_COUNT = 10
    }

    private val chainId = chainAssetProvider.chainId()

    private val coinBackupProgress = MutableStateFlow<BackupProgress>(BackupProgress.Unknown)
    private val voucherBackupProgress = MutableStateFlow<BackupProgress>(BackupProgress.Unknown)

    private val _progress = combine(coinBackupProgress, voucherBackupProgress) { coinBackupProgress, voucherBackupProgress ->
        when {
            coinBackupProgress is BackupProgress.NotStarted && voucherBackupProgress is BackupProgress.NotStarted -> BackupProgress.NotStarted
            coinBackupProgress is BackupProgress.Completed && voucherBackupProgress is BackupProgress.Completed -> BackupProgress.Completed
            coinBackupProgress is BackupProgress.Initial.Completed && voucherBackupProgress is BackupProgress.Initial.Completed -> BackupProgress.Initial.Completed
            coinBackupProgress is BackupProgress.Deep.Completed && voucherBackupProgress is BackupProgress.Deep.Completed -> BackupProgress.Deep.Completed
            coinBackupProgress is BackupProgress.Initial || voucherBackupProgress is BackupProgress.Initial -> BackupProgress.Initial.Syncing
            coinBackupProgress is BackupProgress.Deep || voucherBackupProgress is BackupProgress.Deep -> BackupProgress.Deep.Syncing
            else -> BackupProgress.Unknown
        }
    }

    override fun subscribeProgress() = _progress

    context(scope: ComputationalScope)
    override fun start() {
        scope.launch {
            val isNewAccount = newAccountStorage.requireValue()
            val coinsDeepCompleted = coinsDeepBackupCompletedStorage.requireValue()
            val coinsInitialCompleted = coinsInitialBackupCompletedStorage.requireValue()

            val vouchersInitialCompleted = vouchersInitialBackupCompletedStorage.requireValue()
            val vouchersDeepCompleted = vouchersDeepBackupCompletedStorage.requireValue()

            when {
                coinsDeepCompleted -> coinBackupProgress.value = BackupProgress.Completed
                coinsInitialCompleted -> coinBackupProgress.value = BackupProgress.Initial.Completed
                !isNewAccount -> launch { backupCoins() }
            }

            when {
                vouchersDeepCompleted -> voucherBackupProgress.value = BackupProgress.Completed
                vouchersInitialCompleted -> voucherBackupProgress.value = BackupProgress.Initial.Completed
                !isNewAccount -> launch { backupVouchers() }
            }
        }
    }

    context(scope: ComputationalScope)
    override fun deepSearch() {
        scope.launch {
            if (_progress.first().isInProgress()) return@launch
            launch { backupCoinsDeep() }
            launch { backupVouchersDeep() }
        }
    }

    context(scope: ComputationalScope)
    override fun markAsCompleted() {
        scope.launch {
            if (_progress.first().isInProgress()) return@launch

            coinsDeepBackupCompletedStorage.saveValue(true)
            vouchersDeepBackupCompletedStorage.saveValue(true)

            coinBackupProgress.value = BackupProgress.Completed
            voucherBackupProgress.value = BackupProgress.Completed
        }
    }

    private suspend fun backupCoins() = measureExecution("Restoring coins") {
        var emptyCoinBatchesInARow = 0
        var coinBackupError: Throwable? = null

        var startIndex = coinsRepository.getNextDerivationIndex()
        coinBackupProgress.value = BackupProgress.Initial.Syncing

        while (emptyCoinBatchesInARow < EMPTY_BATCH_COUNT && coinBackupError == null) {
            val coinAccountsToCheck = createCoinsAccountsToCheck(startIndex)

            fetchCoinsOnChainData(coinAccountsToCheck)
                .onSuccess {
                    if (it.isEmpty()) emptyCoinBatchesInARow += 1
                    startIndex += BATCH_SIZE
                    coinsRepository.saveAll(it.toCoinsList(coinAccountsToCheck))
                }
                .onFailure {
                    coinBackupError = it
                }
        }

        coinBackupProgress.value = BackupProgress.Initial.Completed

        if (coinBackupError == null) {
            coinsBackupLastIndexStorage.saveValue(startIndex)
            coinsInitialBackupCompletedStorage.saveValue(true)
            Timber.d("Coin backup is done")
        } else {
            Timber.e(coinBackupError, "Failed to backup coins")
        }
    }

    private suspend fun backupCoinsDeep() = measureExecution("Restoring coins") {
        var exploredBatches = 0
        var error: Throwable? = null

        var startIndex = coinsBackupLastIndexStorage.requireValue()
        coinBackupProgress.value = BackupProgress.Deep.Syncing

        while (exploredBatches < DEEP_SEARCH_BATCH_COUNT && error == null) {
            val coinAccountsToCheck = createCoinsAccountsToCheck(startIndex)

            fetchCoinsOnChainData(coinAccountsToCheck)
                .onSuccess {
                    exploredBatches += 1
                    startIndex += BATCH_SIZE
                    coinsRepository.saveAll(it.toCoinsList(coinAccountsToCheck))
                }
                .onFailure {
                    error = it
                }
        }

        coinBackupProgress.value = BackupProgress.Deep.Completed

        if (error == null) {
            coinsBackupLastIndexStorage.saveValue(startIndex)
            Timber.d("Coin deep backup is done")
        } else {
            Timber.e(error, "Failed to deep backup coins")
        }
    }

    private fun Map<AccountId, OnChainCoinInfo>.toCoinsList(coinAccountsToCheck: Map<AccountId, Int>) = mapNotNull { (accountId, onChainInfo) ->
        Coin(
            derivationIndex = coinAccountsToCheck[accountId] ?: return@mapNotNull null,
            valueExponent = ValueExponent(onChainInfo.value),
            accountId = accountId,
            // Recovered from a read that found it, so it is on chain by construction.
            age = Age.Known(onChainInfo.age),
            isOnChain = true
        )
    }

    private suspend fun createCoinsAccountsToCheck(startIndex: Int) = measureExecution("deriving accounts for coins") {
        val indices = (startIndex until startIndex + BATCH_SIZE).toList()
        keypairDerivation.getDerivedAccountIds(indices)
            .withIndex()
            .associateBy(keySelector = { it.value }, valueTransform = { it.index })
    }

    private suspend fun fetchCoinsOnChainData(coinAccountsToCheck: Map<AccountId, Int>) = measureExecution("fetching on chain data for coins batch") {
        coinsRepository.fetchCoinsInfoFor(chainId, coinAccountsToCheck.keys.toList())
    }
        .map { it.filterNotNull() }

    private suspend fun backupVouchers() = measureExecution("Restoring vouchers") {
        var emptyVoucherBatchesInARow = 0
        var voucherBackupError: Throwable? = null

        var startIndex = voucherRepository.getNextDerivationIndex()
        voucherBackupProgress.value = BackupProgress.Initial.Syncing

        while (emptyVoucherBatchesInARow < EMPTY_BATCH_COUNT && voucherBackupError == null) {
            val voucherKeysToCheck = createVouchersKeysToCheck(startIndex)

            fetchVouchersOnChainData(voucherKeysToCheck.keys.toList())
                .filterNotUnloaded(voucherKeysToCheck)
                .onSuccess { vouchers ->
                    if (vouchers.isEmpty()) emptyVoucherBatchesInARow += 1
                    startIndex += BATCH_SIZE

                    voucherRepository.saveAll(vouchers)
                }
                .onFailure {
                    voucherBackupError = it
                }
        }

        voucherBackupProgress.value = BackupProgress.Initial.Completed

        if (voucherBackupError == null) {
            vouchersBackupLastIndexStorage.saveValue(startIndex)
            vouchersInitialBackupCompletedStorage.saveValue(true)
            Timber.d("Voucher backup is done")
        } else {
            Timber.e(voucherBackupError, "Failed to backup vouchers")
        }
    }

    private suspend fun Result<Pair<Map<BandersnatchPublicKey, ValueExponent>, Map<BandersnatchPublicKey, RingPosition>>>.filterNotUnloaded(
        voucherKeysToCheck: Map<BandersnatchPublicKey, Int>
    ): Result<List<RecyclerVoucher>> = flatMap { (values, records) ->
        val detectedVouchers = records.toVouchersList(voucherKeysToCheck, values)

        val vouchersInRecycler = detectedVouchers.filter { it.location is Location.InRecycler }
        fetchNotUnloadedVouchers(vouchersInRecycler)
            .map {
                val onboardingVouchers = detectedVouchers.filter { it.location is Location.Onboarding }
                it + onboardingVouchers
            }
    }

    private suspend fun fetchNotUnloadedVouchers(detected: List<RecyclerVoucher>): Result<List<RecyclerVoucher>> {
        if (detected.isEmpty()) return Result.success(listOf())
        return coinageInstanceIdProvider.instanceId().flatMap { instanceId ->
            val keys = detected.mapNotNull {
                val location = (it.location as? Location.InRecycler) ?: return@mapNotNull null
                val aliasContext = coinageSigningContextProvider.recyclerVouchersContext()
                val alias = voucherRingDerivation.deriveBandersnatch(it.ringVrfKeyIndex).aliasInContext(aliasContext)

                it to StorageKey4(
                    instanceId.toLong().toBigInteger(),
                    it.recyclerValue.value.toBigInteger(),
                    location.recyclerIndex.value,
                    alias.value
                )
            }.toMap()

            voucherRepository.fetchRecyclerAliasStates(chainId, keys.values.toList())
                .map { aliasStates ->
                    keys
                        .mapValues { (_, value) -> value.fourth.toDataByteArray().toString() }
                        .mapNotNull { if (aliasStates[it.value] is OnChainAliasState.Unloaded) null else it.key }
                }
        }
    }

    private suspend fun backupVouchersDeep() = measureExecution("Restoring vouchers") {
        var exploredBatches = 0
        var error: Throwable? = null

        var startIndex = vouchersBackupLastIndexStorage.requireValue()
        voucherBackupProgress.value = BackupProgress.Deep.Syncing

        while (exploredBatches < DEEP_SEARCH_BATCH_COUNT && error == null) {
            val voucherKeysToCheck = createVouchersKeysToCheck(startIndex)

            fetchVouchersOnChainData(voucherKeysToCheck.keys.toList())
                .filterNotUnloaded(voucherKeysToCheck)
                .onSuccess { vouchers ->
                    exploredBatches += 1
                    startIndex += BATCH_SIZE

                    voucherRepository.saveAll(vouchers)
                }
                .onFailure {
                    error = it
                }
        }

        voucherBackupProgress.value = BackupProgress.Deep.Completed

        if (error == null) {
            vouchersBackupLastIndexStorage.saveValue(startIndex)
            Timber.d("Voucher deep backup is done")
        } else {
            Timber.e(error, "Failed to deep backup vouchers")
        }
    }

    private fun Map<BandersnatchPublicKey, RingPosition>.toVouchersList(
        voucherKeysToCheck: Map<BandersnatchPublicKey, Int>,
        values: Map<BandersnatchPublicKey, ValueExponent>
    ) = mapNotNull { (publicKey, onChainInfo) ->
        RecyclerVoucher(
            ringVrfKeyIndex = voucherKeysToCheck[publicKey] ?: return@mapNotNull null,
            ringVrfPublicKey = publicKey,
            recyclerValue = values[publicKey] ?: return@mapNotNull null,
            location = onChainInfo.getVoucherLocation(),
        )
    }

    private suspend fun createVouchersKeysToCheck(startIndex: Int) = measureExecution("Deriving accounts for vouchers") {
        val indices = (startIndex until startIndex + BATCH_SIZE).toList()
        voucherRingDerivation.getDerivedMemberKeys(indices)
            .withIndex()
            .associateBy(keySelector = { it.value }, valueTransform = { it.index })
    }

    private suspend fun fetchVouchersOnChainData(keys: List<BandersnatchPublicKey>) = measureExecution("Fetching vouchers on chain info") {
        coinageInstanceIdProvider.instanceId().flatMap { instanceId ->
            voucherRepository.fetchValuesForKeys(chainId, instanceId, keys)
                .map { it.filterNotNull() }
                .flatMap { values ->
                    val pairs = values.map { (key, exponent) -> exponent.toRingCollectionId(instanceId) to key }

                    membersRepository.fetchMembers(
                        chainId = chainId,
                        keys = pairs,
                        consistency = CacheableDataConsistency.CONSISTENT_WITH_REMOTE,
                    ).map { recordsByPair ->
                        val recordsByKey = recordsByPair.filterNotNull()
                            .mapKeys { (pair, _) -> pair.second }

                        values to recordsByKey
                    }
                }
        }
    }

    private fun RingPosition.getVoucherLocation() = when (this) {
        // Recovery knows where the voucher sits, not how full the ring is. Zero until the location service
        // reads it, so nothing releases the voucher on an anonymity set we have not seen.
        is RingPosition.Included -> Location.InRecycler(ringIndex, recyclerMembers = 0)
        is RingPosition.Onboarding -> Location.Onboarding
        is RingPosition.Suspended -> Location.Unknown
    }
}
