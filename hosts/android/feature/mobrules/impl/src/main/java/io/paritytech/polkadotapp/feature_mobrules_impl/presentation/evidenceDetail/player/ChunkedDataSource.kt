package io.paritytech.polkadotapp.feature_mobrules_impl.presentation.evidenceDetail.player

import android.net.Uri
import androidx.core.net.toUri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import io.novasama.substrate_sdk_android.extensions.fromHex
import io.paritytech.polkadotapp.common.utils.InformationSize.Companion.bytes
import io.paritytech.polkadotapp.common.utils.mapError
import io.paritytech.polkadotapp.feature_become_citizen_api.data.model.EvidenceMetadata
import io.paritytech.polkadotapp.feature_mobrules_impl.data.evidence.EvidenceContentGateway
import io.paritytech.polkadotapp.feature_mobrules_impl.data.evidence.extractHash
import io.paritytech.polkadotapp.tools_ipfs_api.IpfsContentLookup
import io.paritytech.polkadotapp.tools_ipfs_api.getDefaultRawLink
import kotlinx.coroutines.runBlocking
import timber.log.Timber
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream

@UnstableApi
class ChunkedDataSource(
    private val evidenceContentGateway: EvidenceContentGateway,
    private val contentLookup: IpfsContentLookup,
) : BaseDataSource(true) {
    private var metadata: EvidenceMetadata? = null

    private var chunkSize: Long = -1

    private var currentChunkIndex: Int = 0
    private var currentUri: Uri? = null

    private var bytesRemaining: Long = 0

    private var sourceInputStream: InputStream? = null

    private val cache = mutableMapOf<Int, ByteArray>()

    override fun open(dataSpec: DataSpec): Long {
        if (metadata == null) {
            val metadataHash = dataSpec.uri.extractHash()
            metadata = evidenceContentGateway.getEvidenceMetadata(metadataHash)
        }

        val startPosition = dataSpec.position
        currentChunkIndex = (startPosition / chunkSize).toInt()
        val chunkOffset = (startPosition % chunkSize).toInt()

        openConnection(currentChunkIndex)

        bytesRemaining = if (dataSpec.length == C.LENGTH_UNSET.toLong()) {
            chunkSize - chunkOffset
        } else {
            dataSpec.length
        }

        sourceInputStream?.skip(chunkOffset.toLong())
        return bytesRemaining
    }

    override fun read(buffer: ByteArray, offset: Int, readLength: Int): Int {
        if (bytesRemaining == 0L) {
            return C.RESULT_END_OF_INPUT
        }

        val bytesRead = sourceInputStream?.read(buffer, offset, readLength) ?: -1
        if (bytesRead == -1) {
            closeCurrentConnection()
            currentChunkIndex++
            return if (currentChunkIndex < metadata!!.chunks.size) {
                openConnection(currentChunkIndex)
                read(buffer, offset, readLength)
            } else {
                C.RESULT_END_OF_INPUT
            }
        }

        bytesRemaining -= bytesRead
        return bytesRead
    }

    override fun getUri(): Uri? {
        return currentUri
    }

    override fun close() {
        closeCurrentConnection()
    }

    private fun openConnection(chunkIndex: Int) {
        val currentChunkHash = metadata!!.chunks[chunkIndex].fromHex()
        currentUri = runBlocking { contentLookup.getDefaultRawLink(currentChunkHash) }
            .mapError { IOException("Failed to resolve IPFS chunk link", it) }
            .getOrThrow()
            .toUri()

        if (cache.containsKey(chunkIndex)) {
            Timber.d("Reading the chunk $chunkIndex from cache")
            val chunkData = cache[chunkIndex]!!
            sourceInputStream = ByteArrayInputStream(chunkData)
            Timber.d("Fetched the chunk $chunkIndex from cache")
            return
        }

        Timber.d("Reading the chunk $chunkIndex from networking")

        val chunkData = evidenceContentGateway.getEvidenceChunk(currentChunkHash)

        if (chunkSize == -1L) {
            chunkSize = chunkData.size.bytes.inWholeBytes
        }

        Timber.d("Fetched chunk $chunkIndex from networking, size: ${chunkData.size.bytes}")

        cache[chunkIndex] = chunkData
        sourceInputStream = ByteArrayInputStream(chunkData)
    }

    private fun closeCurrentConnection() {
        sourceInputStream?.close()
        sourceInputStream = null
    }
}
