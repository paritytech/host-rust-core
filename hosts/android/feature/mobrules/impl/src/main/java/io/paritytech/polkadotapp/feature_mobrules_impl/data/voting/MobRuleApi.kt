package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting

import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableModule
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry0
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry1
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry2
import io.paritytech.polkadotapp.chains.storage.source.query.api.constant
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage0
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage1
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage2
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.chains.util.mobRule
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.CaseCount
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobCredit
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleCaseId
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleDoneCase
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.MobRuleOpenCase
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.PayoutDistribution
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.PayoutRoundIndex
import io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model.VotingPoints
import io.paritytech.polkadotapp.feature_mobrules_impl.domain.voting.model.MobRuleVote
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonalAlias
import io.paritytech.polkadotapp.feature_vouchers_api.data.model.PrivacyVoucherDenominationType

@JvmInline
value class MobRuleApi(override val module: Module) : QueryableModule

val RuntimeMetadata.mobRule: MobRuleApi
    get() = MobRuleApi(mobRule())

context(withRuntime: WithRuntime)
val MobRuleApi.caseCount: QueryableStorageEntry0<CaseCount>
    get() = storage0("CaseCount")

context(withRuntime: WithRuntime)
val MobRuleApi.openCases: QueryableStorageEntry1<MobRuleCaseId, MobRuleOpenCase>
    get() = storage1("OpenCases")

context(withRuntime: WithRuntime)
val MobRuleApi.doneCases: QueryableStorageEntry1<MobRuleCaseId, MobRuleDoneCase>
    get() = storage1("DoneCases")

context(withRuntime: WithRuntime)
val MobRuleApi.ripeCases: QueryableStorageEntry1<MobRuleCaseId, MobRuleOpenCase>
    get() = storage1("RipeCases")

context(withRuntime: WithRuntime)
val MobRuleApi.votes: QueryableStorageEntry2<MobRuleCaseId, PersonalAlias, MobRuleVote>
    get() = storage2("Votes")

context(withRuntime: WithRuntime)
val MobRuleApi.payoutDistribution: QueryableStorageEntry0<PayoutDistribution>
    get() = storage0("PayoutDistribution")

context(withRuntime: WithRuntime)
val MobRuleApi.votingPoints: QueryableStorageEntry2<PayoutRoundIndex, PersonalAlias, VotingPoints>
    get() = storage2("VotingPoints")

context(withRuntime: WithRuntime)
val MobRuleApi.credits: QueryableStorageEntry1<PersonalAlias, MobCredit>
    get() = storage1("Credits")

// Constants

context(withRuntime: WithRuntime)
val MobRuleApi.mobRuleVoucherType: PrivacyVoucherDenominationType
    get() = constant("MobRuleVoucherType")
