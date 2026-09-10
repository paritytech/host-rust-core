package io.paritytech.polkadotapp.feature_tokens_impl.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.paritytech.polkadotapp.feature_tokens_api.di.DigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.domain.AssetDisplayMapper
import io.paritytech.polkadotapp.feature_tokens_api.domain.ChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_api.presentation.amountinput.AmountInputMixin
import io.paritytech.polkadotapp.feature_tokens_api.presentation.fee.FeeLoaderMixin
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.ConversionFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.KnownTokenFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.formatter.TokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_api.presentation.mapper.TokenAmountMapper
import io.paritytech.polkadotapp.feature_tokens_impl.domain.RealAssetDisplayMapper
import io.paritytech.polkadotapp.feature_tokens_impl.domain.RealDigitalDollarChainAssetProvider
import io.paritytech.polkadotapp.feature_tokens_impl.presentation.amountinput.AmountInputMixinFactory
import io.paritytech.polkadotapp.feature_tokens_impl.presentation.fee.FeeLoaderMixinFactory
import io.paritytech.polkadotapp.feature_tokens_impl.presentation.formatter.RealConversionFormatter
import io.paritytech.polkadotapp.feature_tokens_impl.presentation.formatter.RealKnownTokenFormatter
import io.paritytech.polkadotapp.feature_tokens_impl.presentation.formatter.RealTokenAmountFormatter
import io.paritytech.polkadotapp.feature_tokens_impl.presentation.mapper.RealTokenAmountMapper
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
internal interface TokensFeatureApiModule {
    @Binds
    fun bindAssetDisplayMapper(assetDisplayMapper: RealAssetDisplayMapper): AssetDisplayMapper

    @Binds
    fun bindKnownTokenFormatter(knownTokenFormatter: RealKnownTokenFormatter): KnownTokenFormatter

    @Binds
    fun bindConversionFormatter(knownTokenFormatter: RealConversionFormatter): ConversionFormatter

    @Binds
    fun bindTokenAmountFormatter(impl: RealTokenAmountFormatter): TokenAmountFormatter

    @Binds
    fun bindAmountInputMixinFactory(impl: AmountInputMixinFactory): AmountInputMixin.Factory

    @Binds
    fun bindFeeLoaderMixinFactory(impl: FeeLoaderMixinFactory): FeeLoaderMixin.Factory

    @Binds
    fun bindTokenAmountMapper(impl: RealTokenAmountMapper): TokenAmountMapper

    @Binds
    @Singleton
    @DigitalDollarChainAssetProvider
    fun bindDigitalDollarChainAssetProvider(impl: RealDigitalDollarChainAssetProvider): ChainAssetProvider
}
