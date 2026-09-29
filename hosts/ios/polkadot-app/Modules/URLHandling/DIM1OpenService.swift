import Foundation
import UIKit

final class DIM1OpenService {
    let host = "tattoo"
}

extension DIM1OpenService: URLHandlingServiceProtocol {
    func handle(url: URL) -> Bool {
        guard url.host() == host else {
            return false
        }

        let list = MainActor.assumeIsolated {
            let view = TattooListViewFactory.createView()
            return view?.controller
        }

        guard let list else {
            return true
        }

        MainActor.assumeIsolated {
            let navigation = AppNavigationController(rootViewController: list)
            navigation.modalPresentationStyle = .fullScreen
            UIWindow.topWindow?.rootViewController?.present(navigation, animated: true)
        }

        return true
    }
}
