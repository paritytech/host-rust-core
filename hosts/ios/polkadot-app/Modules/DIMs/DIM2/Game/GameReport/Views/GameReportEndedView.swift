import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class GameReportEndedView: UIView {
    let actionButton: RoundedButton = create {
        $0.setTitle(String(localized: .Game.gameReportEndedAction))
        $0.apply(style: .white)
    }

    private let iconImageView: UIImageView = create {
        $0.image = UIImage(systemName: "clock")
        $0.tintColor = .white
        $0.contentMode = .scaleAspectFit
    }

    private let titleLabel: Label = create {
        $0.numberOfLines = 0
        $0.textAlignment = .center
        $0.typography = .headlineLarge
        $0.textColor = .fgPrimary
    }

    private let descriptionLabel: Label = create {
        $0.numberOfLines = 0
        $0.textAlignment = .center
        $0.typography = .paragraphLarge
        $0.textColor = .fgSecondary
        $0.text = String(localized: .Game.gameReportEndedDescription)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension GameReportEndedView {
    func bind(title: String) {
        titleLabel.text = title
    }
}

private extension GameReportEndedView {
    func setupLayout() {
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.alignment = .center

        contentStack.addArrangedSubview(iconImageView)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(descriptionLabel)

        contentStack.setCustomSpacing(24, after: iconImageView)
        contentStack.setCustomSpacing(16, after: titleLabel)

        iconImageView.snp.makeConstraints {
            $0.size.equalTo(CGSize(width: 96, height: 96))
        }

        addSubview(contentStack)
        contentStack.snp.makeConstraints {
            $0.centerY.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(40)
        }

        addSubview(actionButton)
        actionButton.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(16)
            $0.height.equalTo(UIConstants.actionHeight)
        }
    }
}
