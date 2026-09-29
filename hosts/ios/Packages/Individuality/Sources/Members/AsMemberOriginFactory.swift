import Foundation
import ExtrinsicService
import KeyDerivation

public protocol AsMemberOriginCreating {
    func createSelfIncludeOrigin(vrfManager: BandersnatchKeyManaging) -> ExtrinsicOriginDefining
}

public final class AsMemberOriginFactory: AsMemberOriginCreating {
    public init() {}

    public func createSelfIncludeOrigin(
        vrfManager: BandersnatchKeyManaging
    ) -> ExtrinsicOriginDefining {
        let asMemberOrigin = AsMemberOriginDefinition(vrfManager: vrfManager)
        let restrictsOrigin = RestrictsOriginDefinition(enabled: false)

        return ExtrinsicCompoundOrigin(children: [restrictsOrigin, asMemberOrigin])
    }
}
