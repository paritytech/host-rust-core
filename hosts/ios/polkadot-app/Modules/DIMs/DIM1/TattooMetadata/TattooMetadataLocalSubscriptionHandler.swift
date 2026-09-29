import Foundation
import Individuality

protocol TattooMetadataLocalSubscriptionHandler {
    func handleTattooMetadata(
        result: Result<TattooMetadata, Error>,
        familyId: ProofOfInkPallet.FamilyId
    )
}

extension TattooMetadataLocalSubscriptionHandler {
    func handleTattooMetadata(
        result _: Result<TattooMetadata, Error>,
        familyId _: ProofOfInkPallet.FamilyId
    ) {}
}
