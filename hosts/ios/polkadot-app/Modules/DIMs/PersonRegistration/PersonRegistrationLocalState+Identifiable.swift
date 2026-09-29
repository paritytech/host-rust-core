import Foundation
import Operation_iOS

extension PersonRegistration.LocalState: Identifiable {
    static let identifier = "io.polkadotapp.PersonRegistration.LocalState.Id"

    var identifier: String {
        Self.identifier
    }
}
