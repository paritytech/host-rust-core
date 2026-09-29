import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class DepositLostViewLayout: UIView {
    private let imageViewCentringView: CenteringWrapperView<UIImageView> = create {
        $0.contentView.contentMode = .scaleAspectFit
    }

    private let labelsContainer: GenericPairValueView<Label, Label> = create {
        $0.spacing = 12

        $0.fView.typography = .headlineLarge
        $0.fView.textColor = .fgPrimary
        $0.fView.numberOfLines = 0
        $0.fView.textAlignment = .center

        $0.sView.typography = .paragraphLarge
        $0.sView.textColor = .fgSecondary
        $0.sView.numberOfLines = 0
        $0.sView.textAlignment = .center
    }

    let closeButton: RoundedButton = create {
        $0.applyMainStyle()
        $0.setTitle(String(localized: .Common.gotIt))
    }

    private var titleLabel: UILabel {
        labelsContainer.fView
    }

    private var subtitleLabel: UILabel {
        labelsContainer.sView
    }

    private var imageView: UIImageView {
        imageViewCentringView.contentView
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        backgroundColor = .bgSurfaceMain

        addSubview(imageViewCentringView)
        imageViewCentringView.snp.makeConstraints {
            $0.top.equalTo(safeAreaLayoutGuide.snp.top)
            $0.leading.trailing.equalToSuperview()
        }

        addSubview(labelsContainer)
        labelsContainer.snp.makeConstraints {
            $0.top.lessThanOrEqualTo(imageViewCentringView.snp.bottom).inset(16)
            $0.centerY.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(32)
        }

        addSubview(closeButton)
        closeButton.snp.makeConstraints {
            $0.top.greaterThanOrEqualTo(labelsContainer.snp.bottom).inset(16)
            $0.leading.trailing.equalToSuperview().inset(32)
            $0.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(32)
            $0.height.equalTo(UIConstants.actionHeight)
        }
    }
}

extension DepositLostViewLayout {
    struct ViewModel {
        let image: UIImage
        let title: String
        let subtitle: String
    }

    func bind(viewModel: ViewModel) {
        imageView.image = viewModel.image
        titleLabel.text = viewModel.title
        subtitleLabel.text = viewModel.subtitle
    }
}
