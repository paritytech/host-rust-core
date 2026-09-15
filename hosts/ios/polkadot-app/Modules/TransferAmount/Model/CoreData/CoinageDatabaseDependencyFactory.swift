import AsyncExtensions
import Foundation
import Operation_iOS
import Coinage
@preconcurrency import SDKLogger
import StructuredConcurrency

// @unchecked: dependencies are effectively immutable + thread-safe; protocols not yet Sendable-annotated
struct CoinageDatabaseDependencyFactory: DatabaseDependencyFactoring, @unchecked Sendable {
    private let storageFacade: StorageFacadeProtocol
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    init(
        storageFacade: StorageFacadeProtocol,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.storageFacade = storageFacade
        self.operationQueue = operationQueue
        self.logger = logger
    }

    func makeCoinRepository() -> AnyDataProviderRepository<Coin> {
        let mapper = CoinMapper()
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        return AnyDataProviderRepository(repository)
    }

    func makeCoinRepository(publicKeys: [PublicKey]) -> AnyDataProviderRepository<Coin> {
        let repository = storageFacade.createRepository(
            filter: NSPredicate(format: "%K IN %@", #keyPath(CDCoin.publicKey), publicKeys.map { $0.toHex() }),
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(CoinMapper())
        )
        return AnyDataProviderRepository(repository)
    }

    func makeTrackedCoinRepository() -> AnyDataProviderRepository<TrackedCoin> {
        let mapper = TrackedCoinMapper()
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        return AnyDataProviderRepository(repository)
    }

    func makeCoinPresenceRepository() -> AnyDataProviderRepository<CoinPresenceUpdate> {
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(CoinPresenceMapper())
        )
        return AnyDataProviderRepository(repository)
    }

    func makeVoucherRepository() -> AnyDataProviderRepository<Voucher> {
        let mapper = VoucherMapper()
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        return AnyDataProviderRepository(repository)
    }

    func makeTrackedVoucherRepository() -> AnyDataProviderRepository<TrackedVoucher> {
        let mapper = TrackedVoucherMapper()
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(mapper)
        )
        return AnyDataProviderRepository(repository)
    }

    func makeVoucherLocationRepository() -> AnyDataProviderRepository<VoucherLocationUpdate> {
        let repository = storageFacade.createRepository(
            filter: nil,
            sortDescriptors: [],
            mapper: AnyCoreDataMapper(VoucherLocationMapper())
        )
        return AnyDataProviderRepository(repository)
    }

    func makeTrackedCoinSnapshotStream() -> AnyAsyncSequence<[TrackedCoin]> {
        storageFacade.databaseService.subscribeSnapshot(
            mapper: AnyCoreDataMapper(TrackedCoinMapper())
        )
    }

    func makeTrackedCoinSnapshotStream(publicKeys: [PublicKey]) -> AnyAsyncSequence<[TrackedCoin]> {
        guard !publicKeys.isEmpty else {
            return AsyncStream<[TrackedCoin]> { $0.finish() }.eraseToAnyAsyncSequence()
        }
        return storageFacade.databaseService.subscribeSnapshot(
            mapper: AnyCoreDataMapper(TrackedCoinMapper()),
            filter: NSPredicate(format: "%K IN %@", #keyPath(CDCoin.publicKey), publicKeys.map { $0.toHex() })
        )
    }

    func makeTrackedVoucherSnapshotStream() -> AnyAsyncSequence<[TrackedVoucher]> {
        storageFacade.databaseService.subscribeSnapshot(
            mapper: AnyCoreDataMapper(TrackedVoucherMapper())
        )
    }
}
