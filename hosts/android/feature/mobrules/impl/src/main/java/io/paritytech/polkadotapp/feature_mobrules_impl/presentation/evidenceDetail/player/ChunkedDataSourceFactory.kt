package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.player

import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import io.paritytech.polkadotapp.feature_mobrules_impl.data.evidence.EvidenceContentGateway
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsContentLookup
import javax.inject.Inject

class ChunkedDataSourceFactory @Inject constructor(
    private val evidenceContentGateway: EvidenceContentGateway,
    private val contentLookup: IpfsContentLookup
) : DataSource.Factory {
    @UnstableApi
    override fun createDataSource(): DataSource {
        return ChunkedDataSource(evidenceContentGateway, contentLookup)
    }
}
