import Foundation

struct Invitation: Hashable {
    enum InvitationType: String {
        case game
        case tattoo
    }

    var type: InvitationType

    var owner: String
    var issuer: String
    var publicKey: String
    var signature: String
}
