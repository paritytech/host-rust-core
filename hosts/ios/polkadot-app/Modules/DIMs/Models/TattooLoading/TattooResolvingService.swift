import Foundation
import Operation_iOS
import SubstrateSdk
import OperationExt
import Individuality

enum TattooResolvingError: Error {
    case cannotGenerateURL
}

protocol TattooResolving {
    func resolveImageUrl(
        for familyId: ProofOfInkPallet.FamilyId,
        index: ProofOfInkPallet.DesignIndex,
        completion: @escaping (Result<URL, Error>) -> Void
    )
}

final class TattooResolutionService {
    let jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol
    private var completion: ((Result<URL, Error>) -> Void)?
    private var index: ProofOfInkPallet.DesignIndex?
    private var tattooMetadataProvider: AnySingleValueProvider<TattooMetadata>?

    init(jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol = JsonDataProviderFactory.shared) {
        self.jsonLocalSubscriptionFactory = jsonLocalSubscriptionFactory
    }
}

extension TattooResolutionService: TattooResolving {
    func resolveImageUrl(
        for familyId: ProofOfInkPallet.FamilyId,
        index: ProofOfInkPallet.DesignIndex,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.index = index
        self.completion = completion
        tattooMetadataProvider?.removeObserver(self)
        tattooMetadataProvider = subscribeToTattooMetadata(for: familyId)
    }
}

extension TattooResolutionService: TattooMetadataLocalSubscriptionHandler, TattooMetadataLocalStorageSubscriber {
    func handleTattooMetadata(result: Result<TattooMetadata, Error>, familyId _: ProofOfInkPallet.FamilyId) {
        switch result {
        case let .success(metadata):
            if let index {
                let url = AppConfig.KnownIPFS.main
                    .appendingPathComponent(metadata.metadata.media)
                    .appendingPathComponent("\(index)")
                completion?(.success(url))
            } else {
                completion?(.failure(TattooResolvingError.cannotGenerateURL))
            }
        case let .failure(error):
            completion?(.failure(error))
        }
    }
}
