package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.tattoo

import android.graphics.pdf.PdfDocument
import io.paritytech.polkadotapp.common.data.storage.file.FileProvider
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.InformationSize.Companion.bytes
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.InstructionsFileSharing
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.instructionGenerator.InstructionGenerator
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.FileOutputStream
import java.io.IOException
import javax.inject.Inject

interface InstructionsAttachmentUseCase {
    suspend fun getInstructionsFileName(tattooId: TattooId, metadata: TattooFamilyMetadata?): String

    suspend fun prepareInstructionsFile(tattooId: TattooId, familyId: ByteArray, metadata: TattooFamilyMetadata?): InstructionsFileSharing
}

private const val INSTRUCTIONS_FILE_EXT = "pdf"
private const val INSTRUCTIONS_FILE_MIME_TYPE = "application/${INSTRUCTIONS_FILE_EXT}"

class RealInstructionsAttachmentUseCase @Inject constructor(
    private val coroutineDispatchers: CoroutineDispatchers,
    private val instructionGenerator: InstructionGenerator,
    private val fileProvider: FileProvider
) : InstructionsAttachmentUseCase {
    override suspend fun getInstructionsFileName(tattooId: TattooId, metadata: TattooFamilyMetadata?): String {
        return if (metadata != null) {
            "${metadata.name}.${INSTRUCTIONS_FILE_EXT}"
        } else {
            "tattoo_${tattooId.familyIndex}.${INSTRUCTIONS_FILE_EXT}"
        }
    }

    override suspend fun prepareInstructionsFile(
        tattooId: TattooId,
        familyId: ByteArray,
        metadata: TattooFamilyMetadata?
    ): InstructionsFileSharing = withContext(coroutineDispatchers.io) {
        val fileName = getInstructionsFileName(tattooId, metadata)
        val file = fileProvider.getFileInInternalCacheStorage(fileName)

        if (file.exists().not()) {
            val document = PdfDocument()

            instructionGenerator.generatePdfInto(document, tattooId, familyId)

            try {
                val fileOutputStream = FileOutputStream(file)
                document.writeTo(fileOutputStream)
                fileOutputStream.close()
            } catch (e: IOException) {
                Timber.e(e, "Failed to write pdf into file")
            }

            document.close()
        }

        InstructionsFileSharing(
            uri = fileProvider.uriOf(file),
            size = file.length().bytes,
            mimeType = INSTRUCTIONS_FILE_MIME_TYPE
        )
    }
}
