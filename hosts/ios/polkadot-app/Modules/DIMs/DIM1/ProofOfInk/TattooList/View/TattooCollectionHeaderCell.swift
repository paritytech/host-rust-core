import UIKit
import PolkadotUI
import DesignSystem

final class TattooCollectionHeaderCell: UICollectionViewCell {
    let titleLabel: Label = .create { view in
        view.textColor = .textAndIconsPrimaryDark
        view.typography = .headlineLarge
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

    func bind(title: String) {
        titleLabel.text = title
    }

    private func setupLayout() {
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
