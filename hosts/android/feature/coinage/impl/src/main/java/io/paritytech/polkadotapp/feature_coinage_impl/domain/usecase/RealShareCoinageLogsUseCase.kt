package io.paritytech.polkadotapp.feature_coinage_impl.domain.usecase

import io.paritytech.polkadotapp.common.data.storage.file.FileProvider
import io.paritytech.polkadotapp.common.presentation.sharing.SharingManager
import io.paritytech.polkadotapp.common.utils.ContentSharing
import io.paritytech.polkadotapp.common.utils.logging.LoggerConstants
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.ShareCoinageLogsUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.CoinRepository
import io.paritytech.polkadotapp.feature_coinage_impl.data.repository.VoucherRepository
import io.paritytech.polkadotapp.feature_coinage_impl.domain.COINAGE_LOG_TAG
import kotlinx.coroutines.flow.first
import javax.inject.Inject

class RealShareCoinageLogsUseCase @Inject constructor(
    private val fileProvider: FileProvider,
    private val sharingManager: SharingManager,
    private val coinRepository: CoinRepository,
    private val voucherRepository: VoucherRepository
) : ShareCoinageLogsUseCase {
    override suspend operator fun invoke(): Result<Unit> = runCatching {
        val appLogFile = fileProvider.getFileInScopedStorage(
            "${LoggerConstants.LOGS_DIR}/${LoggerConstants.LOGS_FILE_NAME}"
        )
        val outputFile = fileProvider.getFileInInternalCacheStorage("coinage_debug.txt")
        outputFile.delete()

        outputFile.bufferedWriter().use { writer ->
            writer.appendLine("=== COINAGE TRANSACTION LOGS ===")
            if (appLogFile.exists()) {
                appLogFile.useLines { lines ->
                    lines.filter { COINAGE_LOG_TAG in it }
                        .forEach { writer.appendLine(it) }
                }
            }

            writer.appendLine("\n=== ALL COINS ===")
            coinRepository.subscribeAllCoins().first().forEach { coin ->
                writer.appendLine("Coin[idx=${coin.derivationIndex}, exp=${coin.valueExponent.value}, age=${coin.age}]")
            }

            writer.appendLine("\n=== ALL VOUCHERS ===")
            voucherRepository.subscribeAllVouchers().first().forEach { voucher ->
                writer.appendLine("Voucher[ringIdx=${voucher.ringVrfKeyIndex}, exp=${voucher.recyclerValue.value}, loc=${voucher.location}]")
            }
        }

        sharingManager.shareContent(
            ContentSharing.file(
                subject = "Coinage Debug Logs",
                uri = fileProvider.uriOf(outputFile),
                mimeType = "text/plain"
            )
        )
    }
}
