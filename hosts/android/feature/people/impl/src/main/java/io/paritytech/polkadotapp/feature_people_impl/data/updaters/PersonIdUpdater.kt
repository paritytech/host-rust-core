package io.paritytech.polkadotapp.feature_people_impl.data.updaters

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.withRuntime
import io.paritytech.polkadotapp.chains.network.updaters.Updater
import io.paritytech.polkadotapp.chains.network.updaters.noSideAffects
import io.paritytech.polkadotapp.chains.storage.source.StorageDataSource
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getMemberKey
import io.paritytech.polkadotapp.feature_account_api.domain.model.MetaAccount
import io.paritytech.polkadotapp.feature_account_api.domain.model.PersonPublicKey
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.keys
import io.paritytech.polkadotapp.feature_people_impl.data.network.blockchain.api.people
import io.paritytech.polkadotapp.feature_people_impl.data.storage.PersonIdStorage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.onEach

/**
 * This updater is needed for syncing personId in **foreground**
 * It will not sync updates in background as the default connection pool stops all active connections when app goes to background
 *
 * That's why [EvidenceUploader.UploadSession] has its own for fetching personId from chain and the uploading state machine writes to [personIdStorage] as well
 */
class PersonIdUpdater(
    override val scope: Updater.NoChainScope<MetaAccount>,
    private val chainRegistry: ChainRegistry,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val personIdStorage: PersonIdStorage,
    private val dataSource: StorageDataSource
) : Updater<MetaAccount> {
    override suspend fun listenForUpdates(
        scopeValue: MetaAccount,
        context: Updater.Context
    ): Flow<Updater.SideEffect> {
        return chainRegistry.withRuntime(context.chain.id) {
            val memberKey = bandersnatchSecretsStorage.getMemberKey(scopeValue.id)

            subscribeToPersonId(memberKey, context)
                .filterNotNull()
                .onEach { personId -> personIdStorage.savePersonId(personId) }
                .noSideAffects()
        }
    }

    private suspend fun subscribeToPersonId(memberKey: PersonPublicKey, context: Updater.Context): Flow<PersonId?> {
        return dataSource.subscribe(context.chain.id, context.storageSubscriptionBuilder) {
            runtime.metadata.people.keys.observe(memberKey)
        }
    }
}
