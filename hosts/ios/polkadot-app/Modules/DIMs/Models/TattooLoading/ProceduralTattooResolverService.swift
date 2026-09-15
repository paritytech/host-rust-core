import Foundation
import SubstrateSdk
import OperationExt
import Individuality
import SubstrateSdkExt

enum ProceduralTattoo {
    case procedural(ProofOfInkPallet.ProceduralSeed)
    case proceduralAccount(AccountId)
    case proceduralPersonal(ProofOfInkPallet.PersonalId)
}

struct ProceduralTattooInput {
    let generationScriptUrl: URL
    let scriptInput: String
}

protocol ProceduralTattooResolving {
    func resolveImageUrl(
        for familyId: ProofOfInkPallet.FamilyId,
        for tattoo: ProceduralTattoo,
        completion: @escaping (Result<ProceduralTattooInput, Error>) -> Void
    )
}

final class ProceduralTattooResolverService {
    let jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol
    private var completion: ((Result<ProceduralTattooInput, Error>) -> Void)?
    private var tattooMetadataProvider: AnySingleValueProvider<TattooMetadata>?
    private var tattoo: ProceduralTattoo?
    init(jsonLocalSubscriptionFactory: JsonDataProviderFactoryProtocol = JsonDataProviderFactory.shared) {
        self.jsonLocalSubscriptionFactory = jsonLocalSubscriptionFactory
    }
}

extension ProceduralTattooResolverService: ProceduralTattooResolving {
    func resolveImageUrl(
        for familyId: ProofOfInkPallet.FamilyId,
        for tattoo: ProceduralTattoo,
        completion: @escaping (Result<ProceduralTattooInput, Error>) -> Void
    ) {
        self.tattoo = tattoo
        self.completion = completion
        tattooMetadataProvider?.removeObserver(self)
        tattooMetadataProvider = subscribeToTattooMetadata(for: familyId)
    }
}

private extension ProceduralTattooResolverService {
    func generateInput(for tattoo: ProceduralTattoo) -> String? {
        switch tattoo {
        case let .procedural(proceduralSeed):
            return asFormatedInput([UInt8](proceduralSeed))
        case let .proceduralAccount(accountId):
            if let formattedAddress = try? accountId.toAddress(using: .substrate(42)) {
                return "'\(formattedAddress)'"
            }
            return nil
        case let .proceduralPersonal(personalId):
            return "\(personalId)"
        }
    }

    func asFormatedInput(_ input: [UInt8]) -> String {
        let valuesAsString = input
            .map { String($0) }
            .joined(separator: ",")
        return "[\(valuesAsString)]"
    }
}

extension ProceduralTattooResolverService: TattooMetadataLocalSubscriptionHandler,
    TattooMetadataLocalStorageSubscriber {
    func handleTattooMetadata(result: Result<TattooMetadata, Error>, familyId _: ProofOfInkPallet.FamilyId) {
        switch result {
        case let .success(metadata):
            if let tattoo,
               let scriptInput = generateInput(for: tattoo) {
                let scriptUrl = AppConfig.KnownIPFS.main
                    .appendingPathComponent(metadata.metadata.media)
                let input = ProceduralTattooInput(
                    generationScriptUrl: scriptUrl,
                    scriptInput: scriptInput
                )
                completion?(.success(input))
            } else {
                completion?(.failure(TattooResolvingError.cannotGenerateURL))
            }
        case let .failure(error):
            completion?(.failure(error))
        }
    }
}
