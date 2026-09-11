package io.paritytech.polkadotapp.feature_videogame_impl.di

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.chains.network.updaters.system.UpdateSystemFactory
import io.paritytech.polkadotapp.feature_videogame_api.data.updaters.VideoGameUpdateSystem
import io.paritytech.polkadotapp.feature_videogame_api.data.updaters.VideoGameUpdaters
import io.paritytech.polkadotapp.feature_videogame_impl.data.updaters.*
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.renderer.GameResultRenderer
import kotlinx.serialization.json.Json
import javax.inject.Qualifier

@InstallIn(SingletonComponent::class)
@Module
class VideoGameFeatureProvidersModule {
    @Provides
    fun provideVideoGameUpdaters(
        scoreAsAccountUpdater: ScoreAsAccountUpdater,
        scoreAsPersonUpdater: ScoreAsPersonUpdater,
        gamePlayerAsAccountUpdater: GamePlayerAsAccountUpdater,
        gamePlayerAsPersonUpdater: GamePlayerAsPersonUpdater,
        gameArchivedPlayerAsAccountUpdater: GameArchivedPlayerAsAccountUpdater,
        personhoodScoreThresholdUpdater: PersonhoodScoreThresholdUpdater
    ): VideoGameUpdaters {
        return VideoGameUpdaters(
            peopleChainUpdaters = listOf(
                scoreAsAccountUpdater,
                scoreAsPersonUpdater,
                gamePlayerAsAccountUpdater,
                gamePlayerAsPersonUpdater,
                gameArchivedPlayerAsAccountUpdater,
                personhoodScoreThresholdUpdater
            )
        )
    }

    @Provides
    fun provideVideoGameUpdateSystem(
        updateSystemFactory: UpdateSystemFactory,
        videoGameUpdaters: VideoGameUpdaters,
        knownChains: KnownChains
    ): VideoGameUpdateSystem {
        val system = updateSystemFactory.createConstantSingleChain(
            updaters = videoGameUpdaters.peopleChainUpdaters,
            chainId = knownChains.people
        )

        return VideoGameUpdateSystem(system)
    }

    @Provides
    fun provideGameResultRenderer(
        @ApplicationContext context: Context
    ) = GameResultRenderer(context)

    @Provides
    @WebViewPayloadJson
    fun provideWebViewPayloadJson(): Json = Json { explicitNulls = false }
}

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class WebViewPayloadJson
