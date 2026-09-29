package io.paritytech.polkadotapp.feature_mobrules_impl.data.evidence

import io.paritytech.polkadotapp.common.data.network.NetworkApiCreator
import io.paritytech.polkadotapp.common.data.network.create
import io.paritytech.polkadotapp.common.utils.mapError
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.EvidenceMetadata
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsContentLookup
import io.paritytech.polkadotapp.tools_ipfs_api.getDefaultJsonLink
import io.paritytech.polkadotapp.tools_ipfs_api.getDefaultRawLink
import kotlinx.coroutines.runBlocking
import retrofit2.Call
import retrofit2.http.GET
import retrofit2.http.Url
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject

interface EvidenceContentGateway {
    fun getEvidenceMetadata(metadataHash: ByteArray): EvidenceMetadata

    fun getEvidenceChunk(chunkHash: ByteArray): ByteArray
}

class IpfsEvidenceContentGateway @Inject constructor(
    private val lookup: IpfsContentLookup,
    private val apiCreator: NetworkApiCreator,
) : EvidenceContentGateway {
    private val api: EvidenceApi = apiCreator.create()

    override fun getEvidenceMetadata(metadataHash: ByteArray): EvidenceMetadata {
        val url = runBlocking { lookup.getDefaultJsonLink(metadataHash) }
            .mapError { IOException("Failed to resolve IPFS metadata link", it) }
            .getOrThrow()
        return api.getMetadata(url).execute().body()!!
    }

    override fun getEvidenceChunk(chunkHash: ByteArray): ByteArray {
        val rawLink = runBlocking { lookup.getDefaultRawLink(chunkHash) }
            .mapError { IOException("Failed to resolve IPFS chunk link", it) }
            .getOrThrow()
        val url = URL(rawLink)
        val connection = url.openConnection() as HttpURLConnection

        connection.run {
            requestMethod = "GET"
            connect()

            if (responseCode != HttpURLConnection.HTTP_OK) {
                throw IOException("Failed to fetch chunk: $responseCode")
            }

            val byteStream = ByteArrayOutputStream()
            inputStream?.copyTo(byteStream)

            return byteStream.toByteArray()
        }
    }

    private interface EvidenceApi {
        @GET
        fun getMetadata(@Url url: String): Call<EvidenceMetadata>
    }
}
