package io.paritytech.polkadotapp.feature_people_impl.data.signer.origins.extension

import io.novasama.substrate_sdk_android.hash.Hasher.blake2b256
import io.novasama.substrate_sdk_android.runtime.RuntimeSnapshot
import io.novasama.substrate_sdk_android.runtime.extrinsic.v5.transactionExtension.InheritedImplication
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchContext
import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.getChainIdByGenesisHashOrThrow
import io.paritytech.polkadotapp.chains.util.findGenesisHashOrThrow
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleCollection
import io.paritytech.polkadotapp.feature_people_api.domain.PeopleMembershipProver

class AsPersonalAliasWithProof(
    private val context: BandersnatchContext,
    private val peopleMembershipProver: PeopleMembershipProver,
    private val chainRegistry: ChainRegistry,
) : AsPersonTransactionExtension() {
    override suspend fun explicit(
        inheritedImplication: InheritedImplication,
        runtimeSnapshot: RuntimeSnapshot
    ): Any {
        val chainId = chainRegistry.getChainIdByGenesisHashOrThrow(inheritedImplication.findGenesisHashOrThrow())
        val message = inheritedImplication.encoded().blake2b256()

        val result = peopleMembershipProver
            .proofPersonMembership(message, context, chainId, PeopleCollection.People)
            .getOrThrow()

        return AsPersonInfo.AsPersonalAliasWithProof(result.proof, context, result.ringIndex, result.revision).toEncodableInstance()
    }
}
