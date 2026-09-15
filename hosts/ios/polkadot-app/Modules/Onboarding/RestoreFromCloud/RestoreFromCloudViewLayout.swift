import UIKit
import PolkadotUI

final class RestoreFromCloudViewLayout: UIView {
    private let activityIndicatorView = ActivityIndicatorView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - ViewModel

extension RestoreFromCloudViewLayout {
    struct ViewModel {
        let isInProgress: Bool
    }

    func bind(viewModel: ViewModel) {
        if viewModel.isInProgress {
            activityIndicatorView.text = String(localized: .recoveringAccountDescription)
            activityIndicatorView.startAnimating()
        } else {
            activityIndicatorView.stopAnimating()
        }
    }
}

// MARK: - Private

private extension RestoreFromCloudViewLayout {
    func setupLayout() {
        backgroundColor = .bgSurfaceMain

        addSubview(activityIndicatorView)
        activityIndicatorView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(32)
            $0.centerY.equalToSuperview()
        }
    }
}
