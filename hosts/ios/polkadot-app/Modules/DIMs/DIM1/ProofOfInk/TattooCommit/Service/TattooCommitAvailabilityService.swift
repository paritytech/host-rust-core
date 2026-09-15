import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery
import Individuality

enum TattooCommitAvailabilityError: Error {
    case busy
}

protocol TattooCommitAvailabilityServicing {
    func checkAvailability() async throws
}

final class TattooCommitAvailabilityService {
    private let connection: JSONRPCEngine
    private let runtimeProvider: RuntimeCodingServiceProtocol
    private let storageRequestFactory: StorageRequestFactoryProtocol

    init(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        operationQueue: OperationQueue
    ) {
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }
}

extension TattooCommitAvailabilityService: TattooCommitAvailabilityServicing {
    func checkAvailability() async throws {
        let codingFactory = try await runtimeProvider
            .fetchCoderFactoryOperation().asyncExecute()

        async let configResponse: StorageResponse<ProofOfInkPallet.ConfigRecord> =
            storageRequestFactory.queryItem(
                engine: connection,
                factory: { codingFactory },
                storagePath: ProofOfInkPallet.configPath
            )
            .asyncExecute()

        async let allocResponse: StorageResponse<StringScaleMapper<ProofOfInkPallet.AllocationCount>> =
            storageRequestFactory.queryItem(
                engine: connection,
                factory: { codingFactory },
                storagePath: ProofOfInkPallet.allocationCountPath
            )
            .asyncExecute()

        let config = try await configResponse.value
        let allocCount = try await allocResponse.value?.value ?? 0

        guard let maximum = config?.maximum else { return }
        guard allocCount < maximum else {
            throw TattooCommitAvailabilityError.busy
        }
    }
}
