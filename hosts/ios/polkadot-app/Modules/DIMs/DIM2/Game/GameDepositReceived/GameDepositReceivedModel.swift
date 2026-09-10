import Foundation

struct GameDepositReceivedModel {
    let registerButtonAvailable: Bool
    let registerHandler: () -> Void
    let skipHandler: () -> Void
}
