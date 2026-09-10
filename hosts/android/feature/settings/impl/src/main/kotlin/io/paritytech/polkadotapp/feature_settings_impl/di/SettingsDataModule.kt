package io.paritytech.polkadotapp.feature_settings_impl.di

import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.paritytech.polkadotapp.common.data.storage.SingleValueStorageFactory
import io.paritytech.polkadotapp.feature_settings_api.domain.language.AppLanguageProvider
import io.paritytech.polkadotapp.feature_settings_impl.data.repository.LanguageRepository
import io.paritytech.polkadotapp.feature_settings_impl.data.repository.RealAppLanguageProvider
import io.paritytech.polkadotapp.feature_settings_impl.data.repository.RealLanguageRepository
import io.paritytech.polkadotapp.feature_settings_impl.data.storage.LanguageStorage
import io.paritytech.polkadotapp.feature_settings_impl.data.storage.createLanguageStorage

@Module
@InstallIn(SingletonComponent::class)
internal interface SettingsDataModule {
    companion object {
        @Provides
        fun provideLanguageStorage(factory: SingleValueStorageFactory): LanguageStorage {
            return factory.createLanguageStorage()
        }
    }

    @Binds
    fun bindLanguageRepository(impl: RealLanguageRepository): LanguageRepository

    @Binds
    fun bindAppLanguageProvider(impl: RealAppLanguageProvider): AppLanguageProvider
}
