import UIKit
import UIKitExt

final class BalanceInfoWireframe: BalanceInfoWireframeProtocol {
    func showAvailableNowInfo(from view: ControllerBackedProtocol?) {
        let models = [
            PrivacyLearnMoreModel(
                title: String(localized: .Transfer.balanceInfoAvailableNowInfoSection1Title),
                details: [
                    String(localized: .Transfer.balanceInfoAvailableNowInfoSection1Detail1),
                    String(localized: .Transfer.balanceInfoAvailableNowInfoSection1Detail2)
                ]
            ),
            PrivacyLearnMoreModel(
                title: String(localized: .Transfer.balanceInfoAvailableNowInfoSection2Title),
                details: [
                    String(localized: .Transfer.balanceInfoAvailableNowInfoSection2Detail1),
                    String(localized: .Transfer.balanceInfoAvailableNowInfoSection2Detail2)
                ]
            )
        ]
        let viewController = PrivacyLearnMoreViewController(models: models)
        view?.controller.navigationController?.pushViewController(viewController, animated: true)
    }

    func showAvailableSoonInfo(from view: ControllerBackedProtocol?) {
        let model = PrivacyLearnMoreModel(
            title: String(localized: .Transfer.balanceInfoAvailableSoonInfoTitle),
            details: [
                String(localized: .Transfer.balanceInfoAvailableSoonInfoDetail1),
                String(localized: .Transfer.balanceInfoAvailableSoonInfoDetail2),
                String(localized: .Transfer.balanceInfoAvailableSoonInfoDetail3)
            ]
        )
        let controller = PrivacyLearnMoreViewController(models: [model])
        view?.controller.navigationController?.pushViewController(controller, animated: true)
    }
}
