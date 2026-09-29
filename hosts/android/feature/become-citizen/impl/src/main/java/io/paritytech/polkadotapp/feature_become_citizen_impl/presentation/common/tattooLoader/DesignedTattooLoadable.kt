package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.tattooLoader

import io.paritytech.polkadotapp.common.data.image.loadables.UrlImageLoadable
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_become_citizen_api.data.repository.TattooRepository
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsContentLookup

class DesignedTattooLoadable(
    private val tattooId: TattooId.DesignedElective,
    private val familyId: ByteArray,
    private val tattooRepository: TattooRepository,
    private val ipfsContentLookup: IpfsContentLookup
) : UrlImageLoadable {
    override suspend fun getUrl(): String? {
        val metadata = tattooRepository.getTattooFamilyMetadata(familyId).getOrNull() ?: return null
        val familyUrl = ipfsContentLookup.getIpfsLinkFor(metadata.cid)
            .logFailure("Failed to resolve IPFS link for designed tattoo")
            .getOrNull() ?: return null

        return "$familyUrl/${tattooId.index}"
    }
}
