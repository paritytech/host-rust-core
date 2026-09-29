package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped
import io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor.RealVideoGamePlayInteractor
import io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor.VideoGamePlayInteractor

@Module
@InstallIn(ViewModelComponent::class)
interface VideoGamePlayModule {
    @Binds
    @ViewModelScoped
    fun bindVideoGamePlayInteractor(impl: RealVideoGamePlayInteractor): VideoGamePlayInteractor
}
