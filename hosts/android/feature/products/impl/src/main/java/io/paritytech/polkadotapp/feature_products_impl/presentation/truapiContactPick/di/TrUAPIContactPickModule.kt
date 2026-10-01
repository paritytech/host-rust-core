package io.paritytech.polkadotapp.feature_products_impl.presentation.truapiContactPick.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIContactPickContext
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIContactPickContextHolder

@Module
@InstallIn(ViewModelComponent::class)
class TrUAPIContactPickModule {
    @Provides
    fun provideTrUAPIContactPickContext(
        holder: TrUAPIContactPickContextHolder,
    ): TrUAPIContactPickContext {
        return requireNotNull(holder.get()) {
            "TrUAPIContactPickContext is not set."
        }
    }
}
