import Foundation
import UIKit
internal import UIKit_iOS

public enum DIM2FooterConfiguration {
    public static func switchDIM(
        inProgress: Bool,
        handler: @escaping () -> Void
    ) -> any HashableContentConfiguration {
        let viewModel = SwitchDimFooterView.ViewModel(
            text: String(localized: .dim2FooterSwitchDim),
            inProgress: inProgress,
            action: handler
        )
        let view = SwitchDimFooterView(viewModel: viewModel)
        return SwiftUIContentConfiguration(view: view)
    }
}
