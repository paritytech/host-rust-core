import UIKit
import DesignSystem
import PolkadotUI
import SnapKit

/// Composes the scan panel's content so Common/QRScanner stays free of contact-search knowledge.
final class ScanPanelViewController: UIViewController {
    private let scannerController: UIViewController
    private let onSearchTap: () -> Void
    private let searchButton = SearchContactFieldButton()

    init(scannerController: UIViewController, onSearchTap: @escaping () -> Void) {
        self.scannerController = scannerController
        self.onSearchTap = onSearchTap
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(scannerController)
        view.addSubview(scannerController.view)
        scannerController.didMove(toParent: self)

        searchButton.onTap = { [weak self] in
            self?.onSearchTap()
        }
        view.addSubview(searchButton)

        setupLayout()
    }
}

private extension ScanPanelViewController {
    func setupLayout() {
        scannerController.view.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
        }

        searchButton.snp.makeConstraints {
            $0.top.equalTo(scannerController.view.snp.bottom)
            $0.leading.trailing.equalToSuperview().inset(DSSpacings.mediumIncreased)
            $0.bottom.equalToSuperview().inset(DSSpacings.small)
        }
    }
}
