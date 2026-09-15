import UIKit
import PolkadotUI
import DesignSystem

final class TattooFamilyDetailsCollectionHeaderCell: UICollectionViewCell {
    private let stackView = UIStackView()
    private let titleLabel: Label = .create { view in
        view.typography = .headlineLarge
        view.textColor = .fgPrimary
        view.numberOfLines = 0
    }

    private let detailsLabel: Label = .create { view in
        view.typography = .paragraphLarge
        view.textColor = .fgPrimary
        view.numberOfLines = 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(viewModel: TattooFamilyDetailsItem.Header) {
        titleLabel.text = viewModel.title
        detailsLabel.text = viewModel.details
    }
}

private extension TattooFamilyDetailsCollectionHeaderCell {
    func setupLayout() {
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .fill
        stackView.distribution = .equalSpacing

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(detailsLabel)
        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(24)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }
}
