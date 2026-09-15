package io.paritytech.polkadotapp.feature_upgrade_username_impl.di

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import io.paritytech.polkadotapp.feature_upgrade_username_api.presentation.bot.UsernameUpgradedRenderer

@Module
@InstallIn(SingletonComponent::class)
class UpgradeUsernameFeatureProvideModule {
    @Provides
    fun provideUsernameUpgradedRenderer(
        @ApplicationContext context: Context
    ) = UsernameUpgradedRenderer(context)
}
