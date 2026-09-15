package io.paritytech.polkadotapp.feature_coinage_impl.di

import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.paritytech.polkadotapp.chains.network.updaters.system.UpdateSystemFactory
import io.paritytech.polkadotapp.common.data.storage.SingleValueStorageFactory
import io.paritytech.polkadotapp.feature_coinage_api.data.updaters.CoinageUpdateSystem
import io.paritytech.polkadotapp.feature_coinage_api.domain.CoinsInteractor
import io.paritytech.polkadotapp.feature_coinage_api.domain.RecyclerVouchersInteractor
import io.paritytech.polkadotapp.feature_coinage_api.domain.common.CoinAllocator
import io.paritytech.polkadotapp.feature_coinage_api.domain.common.VoucherAllocator
import io.paritytech.polkadotapp.feature_coinage_api.domain.debug.CoinageDebugSettings
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentPlanner
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentService
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentWorkerStarter
import io.paritytech.polkadotapp.feature_coinage_api.domain.recycling.CoinageRecyclingStrategySettings
import io.paritytech.polkadotapp.feature_coinage_api.domain.service.CoinageBackupService
import io.paritytech.polkadotapp.feature_coinage_api.domain.service.CoinageServiceStarter
import io.paritytech.polkadotapp.feature_coinage_api.domain.transaction.CoinageTransactionService
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.ClaimReceivedCoinsUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinAmountBreakdownUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageAssetValueUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageAssetsUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageBalanceConverterUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinagePaymentStatusUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageRecyclingUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageTestnetFundUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.OnboardingUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.PrepareCoinageTransferUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.ShareCoinageLogsUseCase
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.TotalBalanceUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.data.debug.RealCoinageDebugSettings
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.CoinKeypairDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.RealCoinKeypairDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.RealVoucherRingDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.derivation.VoucherRingDerivation
import io.paritytech.polkadotapp.feature_coinage_impl.data.helpers.ConsumedTokenChecker
import io.paritytech.polkadotapp.feature_coinage_impl.data.helpers.RealConsumedTokenChecker
import io.paritytech.polkadotapp.feature_coinage_impl.data.helpers.RealUnloadTokenPeriodCalculator
import io.paritytech.polkadotapp.feature_coinage_impl.data.helpers.UnloadTokenPeriodCalculator
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.CoinRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.CoinageInstanceRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.ExponentBoundsRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.RealCoinRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.RealCoinageInstanceRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.RealExponentBoundsRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.RealRecyclerProofDataProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.RealVoucherRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.RecyclerProofDataProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.VoucherRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.context.CoinageSigningContextProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.signer.context.RealCoinageSigningContextProvider
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.CoinsBackupLastIndexStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.CoinsDeepBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.CoinsInitialBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.RealCoinsBackupLastIndexStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.RealCoinsDeepBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.RealCoinsInitialBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.RealVouchersBackupLastIndexStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.RealVouchersDeepBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.RealVouchersInitialBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.RecyclingStrategyStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.VouchersBackupLastIndexStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.VouchersDeepBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.VouchersInitialBackupCompletedStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.storage.createRecyclingStrategyStorage
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageChainViewFactory
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.CoinageEntryRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.RealCoinageChainViewFactory
import io.paritytech.polkadotapp.feature_coinage_impl.data.transaction.RealCoinageEntryRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.updaters.CoinageInstanceUpdater
import io.paritytech.polkadotapp.feature_coinage_impl.domain.RealCoinsInteractor
import io.paritytech.polkadotapp.feature_coinage_impl.domain.RealVouchersInteractor
import io.paritytech.polkadotapp.feature_coinage_impl.domain.common.RealCoinAllocator
import io.paritytech.polkadotapp.feature_coinage_impl.domain.common.RealVoucherAllocator
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.RealExternalPaymentPlanner
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.RealExternalPaymentService
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.RealExternalPaymentWorkerStarter
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.repository.ExternalPaymentRepository
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.repository.RealExternalPaymentRepository
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.usecase.RealUnloadRecyclerIntoExternalAssetUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.usecase.UnloadRecyclerIntoExternalAssetUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.CoinageTransaction
import io.paritytech.polkadotapp.feature_coinage_impl.domain.model.CoinageTransactionFactory
import io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling.RealCoinageRecyclingStrategySettings
import io.paritytech.polkadotapp.feature_coinage_impl.domain.service.RealCoinageBackupService
import io.paritytech.polkadotapp.feature_coinage_impl.domain.service.RealCoinageServiceStarter
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.RealCoinageTransactionService
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.CoinageRecoveryPass
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.CoinageRecoveryScheduler
import io.paritytech.polkadotapp.feature_coinage_impl.domain.transaction.recovery.RealCoinageRecoveryPass
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.CoinageOnboardingSubmissionUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.CoinageTransferSubmissionUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealClaimReceivedCoinsUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinAmountBreakdownUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinageAssetValueUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinageAssetsUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinageBalanceConverterUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinageOnboardingSubmissionUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinagePaymentStatusUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinageRecyclingUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinageTestnetFundUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealCoinageTransferSubmissionUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealOnboardingUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealPrepareCoinageTransferUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealShareCoinageLogsUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase.RealTotalBalanceUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.worker.WorkManagerCoinageRecoveryScheduler
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object CoinageStorageModule {
    @Provides
    @Singleton
    fun provideRecyclingStrategyStorage(factory: SingleValueStorageFactory): RecyclingStrategyStorage {
        return factory.createRecyclingStrategyStorage()
    }
}

@Module
@InstallIn(SingletonComponent::class)
interface CoinageFeatureModule {
    @Binds
    fun bindCoinageRecyclingStrategySettings(
        impl: RealCoinageRecyclingStrategySettings
    ): CoinageRecyclingStrategySettings

    @Binds
    fun bindCoinsInitialBackupCompletedStorage(impl: RealCoinsInitialBackupCompletedStorage): CoinsInitialBackupCompletedStorage

    @Binds
    fun bindVouchersInitialBackupCompletedStorage(impl: RealVouchersInitialBackupCompletedStorage): VouchersInitialBackupCompletedStorage

    @Binds
    fun bindCoinsDeepBackupCompletedStorage(impl: RealCoinsDeepBackupCompletedStorage): CoinsDeepBackupCompletedStorage

    @Binds
    fun bindVouchersDeepBackupCompletedStorage(impl: RealVouchersDeepBackupCompletedStorage): VouchersDeepBackupCompletedStorage

    @Binds
    fun bindCoinsBackupLastIndexStorage(impl: RealCoinsBackupLastIndexStorage): CoinsBackupLastIndexStorage

    @Binds
    fun bindVouchersBackupLastIndexStorage(impl: RealVouchersBackupLastIndexStorage): VouchersBackupLastIndexStorage

    @Binds
    fun bindCoinageInstanceRepository(impl: RealCoinageInstanceRepository): CoinageInstanceRepository

    @Binds
    fun bindCoinKeypairDerivation(impl: RealCoinKeypairDerivation): CoinKeypairDerivation

    @Binds
    fun bindVoucherRingDerivation(impl: RealVoucherRingDerivation): VoucherRingDerivation

    @Binds
    fun bindCoinAllocator(impl: RealCoinAllocator): CoinAllocator

    @Binds
    fun bindCoinRepository(impl: RealCoinRepository): CoinRepository

    @Binds
    fun bindVoucherAllocator(impl: RealVoucherAllocator): VoucherAllocator

    @Binds
    fun bindVoucherRepository(impl: RealVoucherRepository): VoucherRepository

    @Binds
    fun bindCoinageTestnetFundUseCase(impl: RealCoinageTestnetFundUseCase): CoinageTestnetFundUseCase

    @Binds
    fun bindOnboardingUseCase(impl: RealOnboardingUseCase): OnboardingUseCase

    @Binds
    fun bindCoinageOnboardingSubmissionUseCase(impl: RealCoinageOnboardingSubmissionUseCase): CoinageOnboardingSubmissionUseCase

    @Binds
    fun bindVoucherInteractor(impl: RealVouchersInteractor): RecyclerVouchersInteractor

    @Binds
    fun bindCoinsInteractor(impl: RealCoinsInteractor): CoinsInteractor

    @Binds
    fun bindCoinagePaymentStatusUseCase(impl: RealCoinagePaymentStatusUseCase): CoinagePaymentStatusUseCase

    @Binds
    fun bindCoinageAssetsUseCase(impl: RealCoinageAssetsUseCase): CoinageAssetsUseCase

    @Binds
    fun bindCoinageAssetValueUseCase(impl: RealCoinageAssetValueUseCase): CoinageAssetValueUseCase

    @Binds
    fun bindTotalBalanceUseCase(impl: RealTotalBalanceUseCase): TotalBalanceUseCase

    @Binds
    fun bindExponentBoundsRepository(impl: RealExponentBoundsRepository): ExponentBoundsRepository

    @Binds
    fun bindCoinageServiceStarter(impl: RealCoinageServiceStarter): CoinageServiceStarter

    @Binds
    @Singleton
    fun bindCoinageTransactionService(impl: RealCoinageTransactionService): CoinageTransactionService

    @Binds
    fun bindCoinageEntryRepository(impl: RealCoinageEntryRepository): CoinageEntryRepository

    @Binds
    fun bindCoinageChainViewFactory(impl: RealCoinageChainViewFactory): CoinageChainViewFactory

    @Binds
    fun bindCoinageRecoveryScheduler(impl: WorkManagerCoinageRecoveryScheduler): CoinageRecoveryScheduler

    @Binds
    @Singleton
    fun bindCoinageRecoveryPass(impl: RealCoinageRecoveryPass): CoinageRecoveryPass

    @Binds
    fun bindCoinageBalanceConverterUseCase(impl: RealCoinageBalanceConverterUseCase): CoinageBalanceConverterUseCase

    @Binds
    fun bindCoinageSigningContextProvider(impl: RealCoinageSigningContextProvider): CoinageSigningContextProvider

    @Binds
    fun bindConsumedTokenChecker(impl: RealConsumedTokenChecker): ConsumedTokenChecker

    @Binds
    fun bindCoinAmountBreakdownUseCase(impl: RealCoinAmountBreakdownUseCase): CoinAmountBreakdownUseCase

    @Binds
    fun bindPrepareCoinageTransferUseCase(impl: RealPrepareCoinageTransferUseCase): PrepareCoinageTransferUseCase

    @Binds
    fun bindUnloadTokenPeriodCalculator(impl: RealUnloadTokenPeriodCalculator): UnloadTokenPeriodCalculator

    @Binds
    fun bindRecyclerRevisionProvider(impl: RealRecyclerProofDataProvider): RecyclerProofDataProvider

    @Binds
    fun bindCoinageTransferSubmissionUseCase(impl: RealCoinageTransferSubmissionUseCase): CoinageTransferSubmissionUseCase

    @Binds
    fun bindClaimReceivedCoinsUseCase(impl: RealClaimReceivedCoinsUseCase): ClaimReceivedCoinsUseCase

    @Binds
    fun bindShareCoinageLogsUseCase(impl: RealShareCoinageLogsUseCase): ShareCoinageLogsUseCase

    @Binds
    fun bindCoinageRecyclingUseCase(impl: RealCoinageRecyclingUseCase): CoinageRecyclingUseCase

    @Binds
    @Singleton
    fun bindCoinageBackupService(impl: RealCoinageBackupService): CoinageBackupService

    // --- External payments (RFC-0006 host_payment_request) ---

    @Binds
    @Singleton
    fun bindExternalPaymentRepository(impl: RealExternalPaymentRepository): ExternalPaymentRepository

    @Binds
    @Singleton
    fun bindExternalPaymentService(impl: RealExternalPaymentService): ExternalPaymentService

    @Binds
    @Singleton
    fun bindExternalPaymentWorkerStarter(impl: RealExternalPaymentWorkerStarter): ExternalPaymentWorkerStarter

    @Binds
    fun bindExternalPaymentPlanner(impl: RealExternalPaymentPlanner): ExternalPaymentPlanner

    @Binds
    fun bindUnloadRecyclerIntoExternalAssetUseCase(
        impl: RealUnloadRecyclerIntoExternalAssetUseCase,
    ): UnloadRecyclerIntoExternalAssetUseCase

    @Binds
    fun bindCoinageTransactionFactory(impl: CoinageTransactionFactory): CoinageTransaction.Factory

    @Binds
    @Singleton
    fun bindCoinageDebugSettings(impl: RealCoinageDebugSettings): CoinageDebugSettings

    companion object {
        @Provides
        fun provideCoinageUpdateSystem(
            @DigitalDollarChainAssetProvider chainAssetProvider: ChainAssetProvider,
            updateSystemFactory: UpdateSystemFactory,
            coinageInstanceUpdater: CoinageInstanceUpdater,
        ): CoinageUpdateSystem {
            val updateSystem = updateSystemFactory.createConstantSingleChain(
                listOf(coinageInstanceUpdater),
                chainAssetProvider.chainId()
            )

            return CoinageUpdateSystem(updateSystem)
        }
    }
}
