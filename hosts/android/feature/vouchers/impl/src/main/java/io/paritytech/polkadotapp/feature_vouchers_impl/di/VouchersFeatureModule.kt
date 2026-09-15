package io.paritytech.polkadotapp.feature_vouchers_impl.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.paritytech.polkadotapp.feature_vouchers_api.data.VoucherRepository
import io.paritytech.polkadotapp.feature_vouchers_api.data.VouchersSyncManager
import io.paritytech.polkadotapp.feature_vouchers_api.domain.ClaimVouchersUseCase
import io.paritytech.polkadotapp.feature_vouchers_api.domain.VoucherValueResolver
import io.paritytech.polkadotapp.feature_vouchers_api.domain.VouchersRestoreUseCase
import io.paritytech.polkadotapp.feature_vouchers_impl.data.RealVoucherRepository
import io.paritytech.polkadotapp.feature_vouchers_impl.data.RealVouchersSyncManager
import io.paritytech.polkadotapp.feature_vouchers_impl.data.VoucherInternalRepository
import io.paritytech.polkadotapp.feature_vouchers_impl.data.signer.origin.PrivacyVoucherOrigins
import io.paritytech.polkadotapp.feature_vouchers_impl.data.signer.origin.RealPrivacyVoucherOrigins
import io.paritytech.polkadotapp.feature_vouchers_impl.domain.NoOpVoucherSyncExecutor
import io.paritytech.polkadotapp.feature_vouchers_impl.domain.RealClaimVoucherUseCase
import io.paritytech.polkadotapp.feature_vouchers_impl.domain.RealVouchersRestoreUseCase
import io.paritytech.polkadotapp.feature_vouchers_impl.domain.VoucherSyncExecutor
import io.paritytech.polkadotapp.feature_vouchers_impl.domain.VoucherValueResolverFactory

@Module
@InstallIn(SingletonComponent::class)
interface VouchersFeatureModule {
    @Binds
    fun bindVoucherValueResolverFactory(impl: VoucherValueResolverFactory): VoucherValueResolver.Factory

    @Binds
    fun provideVoucherRepository(impl: RealVoucherRepository): VoucherRepository

    @Binds
    fun provideVoucherInternalRepository(impl: RealVoucherRepository): VoucherInternalRepository

    @Binds
    fun provideVoucherSyncExecutor(impl: NoOpVoucherSyncExecutor): VoucherSyncExecutor

    @Binds
    fun provideVouchersSyncManager(impl: RealVouchersSyncManager): VouchersSyncManager

    @Binds
    fun provideVouchersRestoreUseCase(impl: RealVouchersRestoreUseCase): VouchersRestoreUseCase

    @Binds
    fun providePrivacyVoucherOrigins(impl: RealPrivacyVoucherOrigins): PrivacyVoucherOrigins

    @Binds
    fun provideClaimVouchersUseCase(impl: RealClaimVoucherUseCase): ClaimVouchersUseCase
}
