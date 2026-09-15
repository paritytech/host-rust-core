package io.paritytech.polkadotapp.app.root.domain.debug

import io.paritytech.polkadotapp.common.data.storage.file.FileProvider
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.logging.LoggerConstants
import io.paritytech.polkadotapp.test_shared.any
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mockito.Mockito.mock
import java.io.File
import java.util.zip.ZipFile

class CollectIssueLogsUseCaseTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val fileProvider = mock(FileProvider::class.java)
    private val coroutineDispatchers = mock(CoroutineDispatchers::class.java)

    @Test
    fun `preserves log contents when creating the attachment`() = runBlocking<Unit> {
        val contents = "App started\nA problem occurred: unexpected response\n"
        val logFile = temporaryFolder.newFile("app.log").apply { writeText(contents) }
        val useCase = createUseCase(logFile)

        val archive = useCase().getOrThrow()

        ZipFile(archive).use { zip ->
            val entries = zip.entries().asSequence().associate { entry ->
                entry.name to zip.getInputStream(entry).bufferedReader().use { it.readText() }
            }
            assertEquals(mapOf(LoggerConstants.LOGS_FILE_NAME to contents), entries)
        }
    }

    @Test
    fun `returns missing logs when the file does not exist`() = runBlocking<Unit> {
        val useCase = createUseCase(File(temporaryFolder.root, "missing.log"))

        val result = useCase()

        assertEquals(DebugLogError.MissingLogs, result.exceptionOrNull())
        assertEquals(emptyList<File>(), File(temporaryFolder.root, "cache").listFiles()?.toList())
    }

    private fun createUseCase(logFile: File): CollectIssueLogsUseCase {
        val cache = temporaryFolder.newFolder("cache")
        whenever(coroutineDispatchers.io).thenReturn(Dispatchers.Unconfined)
        whenever(fileProvider.getFileInScopedStorage(LOG_PATH)).thenReturn(logFile)
        whenever(fileProvider.getFileInInternalCacheStorage(any())).thenAnswer { invocation ->
            File(cache, invocation.getArgument<String>(0))
        }
        return CollectIssueLogsUseCase(fileProvider, coroutineDispatchers)
    }

    private companion object {
        const val LOG_PATH = "${LoggerConstants.LOGS_DIR}/${LoggerConstants.LOGS_FILE_NAME}"
    }
}
