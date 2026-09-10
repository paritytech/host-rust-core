import UIKit
import SwiftUI

struct PrivacyLearnMoreModel {
    let title: String
    let details: [String]
}

final class PrivacyLearnMoreViewController: UIHostingController<PrivacyLearnMoreView> {
    init(models: [PrivacyLearnMoreModel]) {
        super.init(rootView: PrivacyLearnMoreView(models: models, onBack: {}))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.onBack = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
