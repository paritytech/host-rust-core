import Foundation
import Operation_iOS

extension EvidenceSubmission.LocalState: Identifiable {
    static let identifier = "io.polkadotapp.EvidenceSubmission.Id"

    var identifier: String {
        Self.identifier
    }
}

extension EvidenceSubmission.Session: Identifiable {}
