package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.tattooLoader

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsContentLookup
import okhttp3.OkHttpClient
import javax.inject.Inject

class RealTattooImageLoader @Inject constructor(
    private val contextManager: ContextManager,
    private val okHttpClient: OkHttpClient,
    private val tattooRepository: TattooRepository,
    private val chainRegistry: ChainRegistry,
    private val ipfsContentLookup: IpfsContentLookup
) : TattooImageLoader {
    override fun getTattooImage(tattooId: TattooId, familyId: ByteArray): TattooImage {
        return when (tattooId) {
            is TattooId.DesignedElective -> TattooImage.ByUrl(
                DesignedTattooLoadable(
                    tattooId = tattooId,
                    familyId = familyId,
                    tattooRepository = tattooRepository,
                    ipfsContentLookup = ipfsContentLookup
                )
            )

            is TattooId.Procedural,
            is TattooId.ProceduralAccount,
            is TattooId.ProceduralPersonal -> TattooImage.ByJs(
                ProceduralTattooLoadable(
                    context = contextManager.applicationContext,
                    familyId = familyId,
                    tattooId = tattooId,
                    okHttpClient = okHttpClient,
                    tattooRepository = tattooRepository,
                    chainRegistry = chainRegistry,
                    ipfsContentLookup = ipfsContentLookup
                )
            )
        }
    }
}
