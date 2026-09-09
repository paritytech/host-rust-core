import Foundation
import BigInt
import SubstrateSdk
import SubstrateStorageQuery
import Operation_iOS
import Individuality
import KeyDerivation
import ChainRegistry

enum FullUsernameAvailability {
    case free
    case notAvailable
    case reservedByUs
    case reclaimExpiredReservation(expiredReservationAccountIds: [AccountId])
}

protocol FullUsernameAvailabilityValidating {
    func checkAvailability(for username: Username) async throws -> FullUsernameAvailability
}

final class FullUsernameAvailabilityValidator {
    private let walletRepo: WalletManagerRepositoryProtocol
    private let chainId: ChainModel.Id
    private let chainRegistry: ChainRegistryProtocol
    private let storageRequestFactory: StorageRequestFactoryProtocol
    private let operationQueue: OperationQueue

    init(
        walletRepo: WalletManagerRepositoryProtocol = .shared,
        chainId: ChainModel.Id = AppConfig.Chains.chatChain,
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue
    ) {
        self.walletRepo = walletRepo
        self.chainId = chainId
        self.chainRegistry = chainRegistry
        self.operationQueue = operationQueue

        storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }
}

extension FullUsernameAvailabilityValidator: FullUsernameAvailabilityValidating {
    func checkAvailability(for username: Username) async throws -> FullUsernameAvailability {
        guard let usernameData = username.value.data(using: .utf8) else {
            throw CheckAvailabilityError.usernameEncodingFailed
        }

        let connection = try chainRegistry.getConnectionOrError(for: chainId)
        let runtimeService = try chainRegistry.getRuntimeProviderOrError(for: chainId)
        let codingFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()

        let hasOwner = try await hasOwner(
            forUsernameData: usernameData,
            connection: connection,
            codingFactory: codingFactory
        )

        if hasOwner {
            return .notAvailable
        }

        let reservations = try await reservationsQueue(
            forUsernameData: usernameData,
            connection: connection,
            codingFactory: codingFactory
        )

        guard let reservations, !reservations.isEmpty else {
            return .free
        }

        guard let accountId = try? walletRepo.main().getRawPublicKey() else {
            throw CheckAvailabilityError.missingAccountId
        }

        async let expirationDuration = try fetchExpirationDuration(
            connection: connection,
            codingFactory: codingFactory
        )

        var expiredReservations: [ResourcesPallet.ReservationQueueEntry] = []

        for reservation in reservations {
            if reservation.account == accountId {
                if expiredReservations.isEmpty {
                    // early exit, our account is first in queue
                    return .reservedByUs
                }

                // found us in queue
                break
            }

            let reservationExpired = try await reservationExpired(
                for: reservation,
                expirationDuration: expirationDuration
            )

            if reservationExpired {
                expiredReservations.append(reservation)
            } else {
                return .notAvailable
            }
        }

        return .reclaimExpiredReservation(
            expiredReservationAccountIds: expiredReservations.map(\.account)
        )
    }

    func reservationExpired(
        for reservation: ResourcesPallet.ReservationQueueEntry,
        expirationDuration: BigUInt?
    ) -> Bool {
        guard let expirationDuration else {
            return false
        }

        let expirationDate = Date(
            timeIntervalSince1970: TimeInterval(reservation.joinedAt) + TimeInterval(expirationDuration)
        )

        return expirationDate <= .now
    }
}

private extension FullUsernameAvailabilityValidator {
    enum CheckAvailabilityError: Error {
        case usernameEncodingFailed
        case missingAccountId
    }

    func hasOwner(
        forUsernameData username: Data,
        connection: JSONRPCEngine,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> Bool {
        let fetchWrapper: CompoundOperationWrapper<
            [StorageResponse<BytesCodable>]
        > = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: username)] },
            factory: { codingFactory },
            storagePath: ResourcesPallet.usernameOwnerOf
        )

        let responses = try await fetchWrapper.asyncExecute()
        return responses.first?.value?.wrappedValue != nil
    }

    func reservationsQueue(
        forUsernameData username: Data,
        connection: JSONRPCEngine,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> [ResourcesPallet.ReservationQueueEntry]? {
        let fetchWrapper: CompoundOperationWrapper<
            [StorageResponse<[ResourcesPallet.ReservationQueueEntry]>]
        > = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: username)] },
            factory: { codingFactory },
            storagePath: ResourcesPallet.usernameReservationQueue
        )

        let responses = try await fetchWrapper.asyncExecute()
        return responses.first?.value
    }

    func fetchExpirationDuration(
        connection: JSONRPCEngine,
        codingFactory: RuntimeCoderFactoryProtocol
    ) async throws -> BigUInt? {
        let fetchWrapper: CompoundOperationWrapper<
            StorageResponse<StringCodable<BigUInt>>
        > = storageRequestFactory.queryItem(
            engine: connection,
            factory: { codingFactory },
            storagePath: ResourcesPallet.usernameReservationDuration
        )

        let duration = try await fetchWrapper.asyncExecute().value?.wrappedValue

        if let duration, duration > 0 {
            return duration
        } else {
            return nil
        }
    }
}
