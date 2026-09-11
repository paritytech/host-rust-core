import UIKit
import SubstrateSdk

protocol AccountShareFactoryProtocol {
    func createSources(
        name: String,
        address: AccountAddress,
        qrImage: UIImage
    ) -> [Any]
}

final class AccountShareFactory {}

extension AccountShareFactory: AccountShareFactoryProtocol {
    func createSources(
        name: String,
        address: AccountAddress,
        qrImage: UIImage
    ) -> [Any] {
        [qrImage, name, address]
    }
}
