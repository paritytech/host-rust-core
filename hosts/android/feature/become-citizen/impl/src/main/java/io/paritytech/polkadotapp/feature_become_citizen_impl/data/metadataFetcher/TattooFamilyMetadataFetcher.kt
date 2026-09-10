package io.paritytech.polkadotapp.feature_become_citizen_impl.data.metadataFetcher

import com.google.gson.Gson
import io.paritytech.polkadotapp.common.utils.await
import io.paritytech.polkadotapp.common.utils.fromJson
import io.paritytech.polkadotapp.common.utils.millimeters
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooPlacement
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooSize
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsContentLookup
import io.paritytech.polkadotapp.tools_ipfs_api.getDefaultRawLink
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration.Companion.seconds

interface TattooFamilyMetadataFetcher {
    suspend fun getMetadata(familyId: ByteArray): Result<TattooFamilyMetadata>
}

private val TIMEOUT = 5.seconds

@Singleton
class RealTattooFamilyMetadataFetcher @Inject constructor(
    private val ipfsContentLookup: IpfsContentLookup,
    private val okHttpClient: OkHttpClient,
    private val gson: Gson
) : TattooFamilyMetadataFetcher {
    private val cachedMetadata = ConcurrentHashMap<Int, TattooFamilyMetadata>()

    override suspend fun getMetadata(familyId: ByteArray): Result<TattooFamilyMetadata> {
        val key = familyId.contentHashCode()
        cachedMetadata[key]?.let { return Result.success(it) }

        return ipfsContentLookup.getDefaultRawLink(familyId).mapCatching { url ->
            val request = Request.Builder().url(url).build()
            // TODO: solve the metadata fetching problem
            val response = withTimeout(TIMEOUT) { okHttpClient.newCall(request).await() }

            val responseModel = gson.fromJson<MetadataResponse>(requireNotNull(response.body.string()))

            TattooFamilyMetadata(
                name = responseModel.metadata.name,
                description = responseModel.metadata.description,
                placement = TattooPlacement(TattooSize.Variable(from = 25.millimeters, to = 50.millimeters)),
                cid = responseModel.metadata.media
            ).also { cachedMetadata[key] = it }
        }
    }

    private class MetadataResponse(
        val metadata: Metadata,
        val version: Int
    ) {
        data class Metadata(
            val description: String,
            val media: String,
            val mime: String,
            val name: String,
            val size: String,
            val type: String
        )
    }
}
