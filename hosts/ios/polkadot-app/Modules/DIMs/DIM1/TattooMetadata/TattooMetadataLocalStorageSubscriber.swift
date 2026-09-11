import Foundation
import BulletinChain
import Operation_iOS
import OperationExt
import Individuality

protocol TattooMetadataLocalStorageSubscriber where Self: AnyObject {
    var jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol { get }

    var tattooMetadataLocalSubscriptionHandler: TattooMetadataLocalSubscriptionHandler { get }

    func subscribeToTattooMetadata(for families: [ProofOfInkPallet.FamilyId])
        -> [AnySingleValueProvider<TattooMetadata>]
    func subscribeToTattooMetadata(for family: ProofOfInkPallet.FamilyId) -> AnySingleValueProvider<TattooMetadata>?
}

extension TattooMetadataLocalStorageSubscriber {
    func subscribeToTattooMetadata(for family: ProofOfInkPallet.FamilyId) -> AnySingleValueProvider<TattooMetadata>? {
        subscribeToTattooMetadata(for: [family]).first
    }

    func subscribeToTattooMetadata(for families: [ProofOfInkPallet.FamilyId])
        -> [AnySingleValueProvider<TattooMetadata>] {
        let displayInfoProviders: [AnySingleValueProvider<TattooMetadata>] = families
            .compactMap { HexToCIDConverter().convertToIPFSURL(
                fileHash: $0.toHexString(),
                codec: .json
            ) }
            .map { jsonLocalSubscriptionFactory.getJson(for: $0) }

        return zip(families, displayInfoProviders)
            .map { familyId, displayInfoProvider in
                let updateClosure: ([DataProviderChange<TattooMetadata>]) -> Void = { [weak self] changes in
                    guard let result = changes.reduceToLastChange() else {
                        return
                    }
                    self?.tattooMetadataLocalSubscriptionHandler.handleTattooMetadata(
                        result: .success(result),
                        familyId: familyId
                    )
                }

                let failureClosure: (Error) -> Void = { [weak self] error in
                    self?.tattooMetadataLocalSubscriptionHandler.handleTattooMetadata(
                        result: .failure(error),
                        familyId: familyId
                    )
                }
                let options = DataProviderObserverOptions(
                    alwaysNotifyOnRefresh: false,
                    waitsInProgressSyncOnAdd: false
                )

                displayInfoProvider.addObserver(
                    self,
                    deliverOn: .main,
                    executing: updateClosure,
                    failing: failureClosure,
                    options: options
                )

                return displayInfoProvider
            }
    }
}

extension TattooMetadataLocalStorageSubscriber where Self: TattooMetadataLocalSubscriptionHandler {
    var tattooMetadataLocalSubscriptionHandler: TattooMetadataLocalSubscriptionHandler { self }
}

// MARK: - AsyncStream conveniences

extension TattooMetadataLocalStorageSubscriber {
    func tattooMetadataStream(
        for familyId: ProofOfInkPallet.FamilyId,
        deliverOn: DispatchQueue = .global()
    ) -> AsyncStream<TattooMetadata?> {
        AsyncStream { continuation in
            guard let url = HexToCIDConverter()
                .convertToIPFSURL(fileHash: familyId.toHexString(), codec: .json)
            else {
                continuation.yield(nil)
                continuation.finish()
                return
            }

            let provider: AnySingleValueProvider<TattooMetadata> = jsonLocalSubscriptionFactory.getJson(for: url)
            let observer = NSObject()
            provider.addObserver(
                observer,
                deliverOn: deliverOn,
                executing: { changes in
                    let last = changes.reduceToLastChange()
                    continuation.yield(last)
                },
                failing: { _ in
                    continuation.yield(nil)
                },
                options: DataProviderObserverOptions(
                    alwaysNotifyOnRefresh: false,
                    waitsInProgressSyncOnAdd: false
                )
            )

            continuation.onTermination = { _ in
                provider.removeObserver(observer)
            }
        }
    }
}
