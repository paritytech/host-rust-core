import UIKit
import Combine
import KeyDerivation
import Keystore_iOS

final class CheckUsernameInteractor {
    weak var presenter: CheckUsernameInteractorOutputProtocol?

    let selectedWallet: WalletManaging
    let usernameStorage: UsernameStoring
    let identityService: IdentityServiceProtocol

    init(
        selectedWallet: WalletManaging,
        identityService: IdentityServiceProtocol,
        usernameStorage: UsernameStoring = UsernameStorage()
    ) {
        self.selectedWallet = selectedWallet
        self.usernameStorage = usernameStorage
        self.identityService = identityService
    }
}

extension CheckUsernameInteractor: CheckUsernameInteractorInputProtocol {
    func onChainUsername() -> AnyPublisher<Username, Error> {
        do {
            let accountId = try selectedWallet.getRawPublicKey()

            return identityService.username(for: accountId)
                .tryMap {
                    guard let username = $0 else {
                        throw IdentityServiceError.accountNotFound
                    }
                    return username
                }
                .eraseToAnyPublisher()
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    func save(username: Username) {
        usernameStorage.username = username
        usernameStorage.usernameClaimed = true
        MainActor.assumeIsolated {
            presenter?.didSaveUsername()
        }
    }
}
