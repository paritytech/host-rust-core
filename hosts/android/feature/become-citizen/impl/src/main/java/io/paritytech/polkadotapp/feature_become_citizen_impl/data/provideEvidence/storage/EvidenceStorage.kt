package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage

import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.common.utils.InformationSize
import io.paritytech.polkadotapp.common.utils.ceilDiv
import io.paritytech.polkadotapp.common.utils.readNBytesCompat
import io.paritytech.polkadotapp.common.utils.skipNBytesCompat
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.ChunkIndex
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.RawEvidence
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.model.RawEvidenceChunk
import okio.use
import java.io.File
import javax.inject.Inject

interface EvidenceStorage {
    fun isEvidenceStored(evidenceType: EvidenceType): Boolean

    fun getFreeStorageSpace(): InformationSize

    fun getEvidenceFile(evidenceType: EvidenceType): File

    suspend fun getRawEvidenceChunk(
        type: EvidenceType,
        chunkIndex: Int,
        chunkSize: InformationSize,
    ): Result<RawEvidenceChunk>

    suspend fun getNumberOfChunks(type: EvidenceType, chunkSize: InformationSize): Int

    suspend fun getRawEvidence(type: EvidenceType): Result<RawEvidence>

    fun getFileName(type: EvidenceType): String
}

suspend fun EvidenceStorage.getFirstChunkIndex(type: EvidenceType, chunkSize: InformationSize): ChunkIndex {
    return ChunkIndex.firstChunkOf(getNumberOfChunks(type, chunkSize))
}

class RealEvidenceStorage @Inject constructor(contextManager: ContextManager) : EvidenceStorage {
    private val appContext = contextManager.applicationContext

    override fun isEvidenceStored(evidenceType: EvidenceType): Boolean {
        return getEvidenceFile(evidenceType).exists()
    }

    override fun getEvidenceFile(evidenceType: EvidenceType): File {
        return File(appContext.filesDir, getFileName(evidenceType))
    }

    override suspend fun getRawEvidenceChunk(
        type: EvidenceType,
        chunkIndex: Int,
        chunkSize: InformationSize,
    ): Result<RawEvidenceChunk> = runCatching {
        val file = getEvidenceFile(type)
        val chunkSizeInBytes = chunkSize.inWholeBytes
        val totalChunks = file.numberOfChunks(chunkSize)

        require(chunkIndex in 0..<totalChunks) {
            "Chunk index out of range"
        }

        val bytesToSkip = chunkIndex.toLong() * chunkSizeInBytes

        val chunk = file.inputStream().use { stream ->
            stream.skipNBytesCompat(bytesToSkip)
            stream.readNBytesCompat(chunkSizeInBytes.toInt())
        }

        RawEvidenceChunk(
            value = chunk,
            isLast = chunkIndex == totalChunks - 1,
            totalSize = file.length()
        )
    }

    override suspend fun getNumberOfChunks(
        type: EvidenceType,
        chunkSize: InformationSize
    ): Int {
        return getEvidenceFile(type).numberOfChunks(chunkSize)
    }

    private fun File.numberOfChunks(chunkSize: InformationSize): Int {
        val chunkSizeInBytes = chunkSize.inWholeBytes
        return length().ceilDiv(chunkSizeInBytes).toInt()
    }

    override suspend fun getRawEvidence(type: EvidenceType): Result<RawEvidence> {
        val file = getEvidenceFile(type)
        return runCatching {
            RawEvidence(file.readBytes())
        }
    }

    override fun getFileName(type: EvidenceType): String {
        return when (type) {
            EvidenceType.PHOTO -> "evidence_photo.jpg"
            EvidenceType.VIDEO -> "evidence_video.mp4"
        }
    }

    override fun getFreeStorageSpace(): InformationSize {
        return InformationSize(appContext.filesDir.freeSpace)
    }
}
