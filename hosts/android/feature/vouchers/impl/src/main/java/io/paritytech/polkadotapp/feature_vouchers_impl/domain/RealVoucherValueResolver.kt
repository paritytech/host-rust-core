package io.paritytech.polkadotapp.feature_vouchers_impl.domain

import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherDenominationType
import io.paritytech.polkadotapp.feature_vouchers_api.domain.VoucherValueResolver
import io.paritytech.polkadotapp.feature_vouchers_api.domain.models.VoucherValue
import io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue.RealVoucherValueRepository
import io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue.VoucherValueRepository
import io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue.dataSource.ForegroundVoucherValueDataSource
import io.paritytech.polkadotapp.feature_vouchers_impl.data.voucherValue.dataSource.VoucherValueDataSource
import javax.inject.Inject

class VoucherValueResolverFactory @Inject constructor(
    foregroundDataSource: ForegroundVoucherValueDataSource,
    private val knownChains: KnownChains
) : VoucherValueResolver.Factory {
    override val foreground: VoucherValueResolver = createResolver(foregroundDataSource)

    private fun createResolver(dataSource: VoucherValueDataSource): VoucherValueResolver {
        val repository = RealVoucherValueRepository(dataSource)
        return RealVoucherValueResolver(repository, knownChains)
    }
}

private class RealVoucherValueResolver(
    private val voucherRepository: VoucherValueRepository,
    private val knownChains: KnownChains
) : VoucherValueResolver {
    override suspend fun resolveVoucherValue(
        voucherDenomination: PrivacyVoucherDenominationType
    ): Result<VoucherValue> {
        return when (voucherDenomination) {
            is PrivacyVoucherDenominationType.Fixed -> {
                Result.success(VoucherValue(voucherDenomination.value))
            }

            is PrivacyVoucherDenominationType.Variable -> {
                val chainId = knownChains.people
                voucherRepository.getVariableVoucherValue(chainId, voucherDenomination.id)
                    .map { VoucherValue(it) }
            }
        }
    }
}
