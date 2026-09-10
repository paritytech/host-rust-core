package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.android.components.ViewModelComponent
import dagger.hilt.android.scopes.ViewModelScoped
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.RealTattooFamilyListInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.family.list.TattooFamilyListInteractor

@Module
@InstallIn(ViewModelComponent::class)
interface TattooReserveModule {
    @Binds
    @ViewModelScoped
    fun bindTattooFamilyListInteractor(impl: RealTattooFamilyListInteractor): TattooFamilyListInteractor
}
