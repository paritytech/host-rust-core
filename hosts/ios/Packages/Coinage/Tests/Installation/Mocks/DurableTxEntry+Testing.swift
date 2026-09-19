import AsyncExtensions
import BigInt
import DurableTransactions
import ExtrinsicService
import Foundation
import Individuality
import KeyDerivation
import os
import SubstrateSdk
@testable import Coinage

extension DurableTxEntry {
    static func registration(
        _ target: InstallationRegistrationTarget,
        id: DurableTxId = UUID(),
        status: DurableTxStatus
    ) -> DurableTxEntry {
        .fixture(id: id, domainId: .coinageInstallation, status: status, groupId: target.registrationGroup)
    }

    func changing(status: DurableTxStatus) -> DurableTxEntry {
        .fixture(
            id: id,
            domainId: domainId,
            checkpoint: checkpoint,
            mortality: mortality,
            successDetectedAt: successDetectedAt,
            status: status,
            groupId: groupId,
            txHash: txHash
        )
    }
}
