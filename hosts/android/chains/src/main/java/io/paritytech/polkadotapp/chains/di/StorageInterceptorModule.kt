package io.paritytech.polkadotapp.chains.di

import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.Multibinds
import io.paritytech.polkadotapp.chains.storage.source.query.intercept.StorageQueryInterceptor

/**
 * Declares the [StorageQueryInterceptor] multibinding so [StorageInterceptorRegistry] can be built even when no
 * feature contributes an interceptor. Features add their own via `@Binds @IntoSet`.
 */
@Module
@InstallIn(SingletonComponent::class)
internal interface StorageInterceptorModule {
    @Multibinds
    fun storageQueryInterceptors(): Set<StorageQueryInterceptor>
}
