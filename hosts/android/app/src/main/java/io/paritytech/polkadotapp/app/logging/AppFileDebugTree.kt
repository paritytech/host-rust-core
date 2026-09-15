package io.paritytech.polkadotapp.app.logging

import io.paritytech.polkadotapp.common.data.storage.file.FileProvider
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.logging.CoroutineFileDebugTree
import io.paritytech.polkadotapp.common.utils.logging.LoggerConstants
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppFileDebugTree @Inject constructor(
    fileProvider: FileProvider,
    coroutineDispatchers: CoroutineDispatchers
) : CoroutineFileDebugTree(
    coroutineScope = CoroutineScope(SupervisorJob() + coroutineDispatchers.io),
    fallbackLogTag = "App",
    logFile = fileProvider.getFileInScopedStorage("${LoggerConstants.LOGS_DIR}/${LoggerConstants.LOGS_FILE_NAME}")
)
