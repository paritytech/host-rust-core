import Foundation
import Foundation_iOS
import PolkadotUI

final class EvidenceInstructionsWireframe: EvidenceInstructionsWireframeProtocol {
    func close(view: EvidenceInstructionsViewProtocol?, completion: (() -> Void)?) {
        view?.controller.dismiss(animated: true, completion: completion)
    }

    func showLowStorage(from view: EvidenceInstructionsViewProtocol?, onProceed: @escaping () -> Void) {
        let viewModel = TitleDetailsSheetViewModel(
            graphics: .lowStorage,
            title: LocalizableResource { _ in
                String(localized: .Tattoo.evidenceLowStorageTitle)
            },
            message: LocalizableResource { _ in
                .normal(String(localized: .Tattoo.evidenceLowStorageDescription))
            },
            mainAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .Tattoo.takeRiskProceed)
                },
                handler: onProceed
            ),
            secondaryAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .Common.gotIt)
                },
                handler: {}
            )
        )

        let bottomSheet = TitleDetailsSheetViewFactory.createView(
            from: viewModel,
            styler: DeviceStatusSheetStyler()
        )

        BottomSheetViewFacade.setupBottomSheet(from: bottomSheet.controller, preferredHeight: nil)
        view?.controller.present(bottomSheet.controller, animated: true)
    }

    func showLowBattery(from view: EvidenceInstructionsViewProtocol?, onProceed: @escaping () -> Void) {
        let viewModel = TitleDetailsSheetViewModel(
            graphics: .lowBattery,
            title: LocalizableResource { _ in
                String(localized: .Tattoo.evidenceLowBatteryTitle)
            },
            message: LocalizableResource { _ in
                .normal(String(localized: .Tattoo.evidenceLowBatteryDescription))
            },
            mainAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .Tattoo.takeRiskProceed)
                },
                handler: onProceed
            ),
            secondaryAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .Common.gotIt)
                },
                handler: {}
            )
        )

        let bottomSheet = TitleDetailsSheetViewFactory.createView(
            from: viewModel,
            styler: DeviceStatusSheetStyler()
        )

        BottomSheetViewFacade.setupBottomSheet(from: bottomSheet.controller, preferredHeight: nil)
        view?.controller.present(bottomSheet.controller, animated: true)
    }
}
