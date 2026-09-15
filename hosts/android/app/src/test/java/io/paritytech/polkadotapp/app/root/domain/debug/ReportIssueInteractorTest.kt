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

class ReportIssueInteractorTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `sends description and both attachments before cleaning the log archive`() = runBlocking<Unit> {
        val logs = temporaryFolder.newFile("app.log").apply { writeText("App diagnostic details") }
        val screenshot = temporaryFolder.newFile("screenshot.png").apply { writeText("Screenshot bytes") }
        val cache = temporaryFolder.newFolder("cache")
        val provider = mock(FileProvider::class.java)
        val dispatchers = mock(CoroutineDispatchers::class.java)
        whenever(dispatchers.io).thenReturn(Dispatchers.Unconfined)
        whenever(provider.getFileInScopedStorage(any())).thenReturn(logs)
        whenever(provider.getFileInInternalCacheStorage(any())).thenAnswer {
            File(cache, it.getArgument<String>(0))
        }
        var received: List<String>? = null
        val api = IssueReportApi { report ->
            received = ZipFile(report.logs).use { archive ->
                listOf(
                    report.description,
                    archive.getInputStream(archive.getEntry(LoggerConstants.LOGS_FILE_NAME)).bufferedReader().use { it.readText() },
                    report.screenshot.readText(),
                )
            }
            Result.success(Unit)
        }
        val interactor = ReportIssueInteractor(CollectIssueLogsUseCase(provider, dispatchers), api, dispatchers)

        interactor.send("  The app froze  ", screenshot).getOrThrow()

        assertEquals(listOf("The app froze", "App diagnostic details", "Screenshot bytes"), received)
        assertEquals(emptyList<File>(), cache.listFiles()?.toList())
        assertEquals("Screenshot bytes", screenshot.readText())
    }
}
