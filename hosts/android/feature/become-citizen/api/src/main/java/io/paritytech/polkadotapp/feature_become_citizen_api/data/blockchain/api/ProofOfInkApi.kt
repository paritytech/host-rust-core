package io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.api

import io.novasama.substrate_sdk_android.runtime.AccountId
import io.novasama.substrate_sdk_android.runtime.metadata.RuntimeMetadata
import io.novasama.substrate_sdk_android.runtime.metadata.module
import io.novasama.substrate_sdk_android.runtime.metadata.module.Module
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableModule
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry0
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry1
import io.paritytech.polkadotapp.chains.storage.source.query.api.QueryableStorageEntry2
import io.paritytech.polkadotapp.chains.storage.source.query.api.constant
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage0
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage1
import io.paritytech.polkadotapp.chains.storage.source.query.api.storage2
import io.paritytech.polkadotapp.chains.util.Modules
import io.paritytech.polkadotapp.chains.util.WithRuntime
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.ProofOfInkCandidate
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.bindProofOfInkConfiguration
import io.paritytech.polkadotapp.feature_become_citizen_api.data.blockchain.models.bindTattooFamily
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.ProofOfInkPerson
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.ProofOfInkReferralTicket
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamily
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooGlobalConfiguration
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import java.math.BigInteger

@JvmInline
value class ProofOfInkApi(override val module: Module) : QueryableModule

val RuntimeMetadata.proofOfInk: ProofOfInkApi
    get() = ProofOfInkApi(module(Modules.PROOF_OF_INK))

context(withRuntime: WithRuntime)
val ProofOfInkApi.designFamilies: QueryableStorageEntry1<BigInteger, TattooFamily>
    get() = storage1("DesignFamilies", binding = { decoded, key -> bindTattooFamily(decoded, key) })

context(withRuntime: WithRuntime)
val ProofOfInkApi.candidates: QueryableStorageEntry1<AccountId, ProofOfInkCandidate?>
    get() = storage1("Candidates")

context(withRuntime: WithRuntime)
val ProofOfInkApi.configuration: QueryableStorageEntry0<TattooGlobalConfiguration>
    get() = storage0("Configuration", binding = { decoded -> bindProofOfInkConfiguration(decoded) })

context(withRuntime: WithRuntime)
val ProofOfInkApi.people: QueryableStorageEntry1<PersonId, ProofOfInkPerson>
    get() = storage1("People")

context(withRuntime: WithRuntime)
val ProofOfInkApi.referralTickets: QueryableStorageEntry1<PersonId, List<ProofOfInkReferralTicket>>
    get() = storage1("ReferralTickets")

context(withRuntime: WithRuntime)
val ProofOfInkApi.committedDesigns: QueryableStorageEntry2<TattooFamilyIndex, BigInteger, Unit>
    get() = storage2(name = "CommittedDesigns", binding = { _, _, _ -> })

context(withRuntime: WithRuntime)
val ProofOfInkApi.pendingInvites: QueryableStorageEntry2<AccountId, AccountId, Unit>
    get() = storage2("PendingInvites")

// Constants

context(withRuntime: WithRuntime)
val ProofOfInkApi.maxActiveReferrals: Int
    get() = constant("MaxActiveReferrals")
