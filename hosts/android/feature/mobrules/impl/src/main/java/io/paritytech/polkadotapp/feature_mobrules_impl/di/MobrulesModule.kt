package io.paritytech.polkadotapp.feature_mobrules_impl.di

import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.ElementsIntoSet
import dagger.multibindings.IntoSet
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.feature_chats_api.domain.extension.ChatExtension
import io.paritytech.polkadotapp.feature_mobrules_api.data.credits.MobRuleCreditsSyncManager
import io.paritytech.polkadotapp.feature_mobrules_api.domain.voting.VotingStatsUseCase
import io.paritytech.polkadotapp.feature_mobrules_impl.data.MOB_RULE
import io.paritytech.polkadotapp.feature_mobrules_impl.data.credits.RealMobRuleCreditsSyncManager
import io.paritytech.polkadotapp.feature_mobrules_impl.data.evidence.EvidenceContentGateway
import io.paritytech.polkadotapp.feature_mobrules_impl.data.evidence.IpfsEvidenceContentGateway
import io.paritytech.polkadotapp.feature_mobrules_impl.data.signer.origin.RealVotingOrigins
import io.paritytech.polkadotapp.feature_mobrules_impl.data.signer.origin.VotingOrigins
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.MobRuleCasesRepository
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.MobRuleVotingStatsRepository
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.RealMobRuleCasesRepository
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.RealMobRuleVotingStatsRepository
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.bot.MobRuleBot
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.MobruleInteractor
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.RealMobruleInteractor
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.RealVotingStateNotifier
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.RealVotingStatsUseCase
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.VotingStateNotifier
import io.paritytech.polkadotapp.feature_people_api.data.AliasContextProvider
import io.paritytech.polkadotapp.feature_people_api.data.SetAliasContext
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
interface MobrulesModule {
    @Binds
    fun bindMobRuleCreditsSyncManager(real: RealMobRuleCreditsSyncManager): MobRuleCreditsSyncManager

    @Binds
    fun bindMobRuleCasesRepository(real: RealMobRuleCasesRepository): MobRuleCasesRepository

    @Binds
    fun bindMobruleVotingInteractor(real: RealMobruleInteractor): MobruleInteractor

    @Binds
    fun bindVotingStateNotifier(impl: RealVotingStateNotifier): VotingStateNotifier

    @Binds
    fun bindEvidenceContentGateway(real: IpfsEvidenceContentGateway): EvidenceContentGateway

    @Binds
    fun bindMobRuleVotingStatsRepository(real: RealMobRuleVotingStatsRepository): MobRuleVotingStatsRepository

    @Binds
    fun bindVotingStatsUseCase(real: RealVotingStatsUseCase): VotingStatsUseCase

    @Binds
    fun bindVotingOrigins(real: RealVotingOrigins): VotingOrigins

    @Binds
    @Singleton
    @IntoSet
    fun bindMobRuleBot(impl: MobRuleBot): ChatExtension

    companion object {
        @Provides
        @ElementsIntoSet
        @SetAliasContext
        fun provideMobRuleContext(): Set<AliasContextProvider> = setOf(AliasContextProvider { BandersnatchContext.MOB_RULE })
    }
}
