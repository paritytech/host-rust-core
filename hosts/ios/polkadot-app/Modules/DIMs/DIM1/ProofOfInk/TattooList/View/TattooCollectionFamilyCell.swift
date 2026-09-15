import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

final class TattooCollectionFamilyCell: UICollectionViewCell {
    let titleLabel: Label = .create { view in
        view.typography = .headlineSmall
        view.textColor = .fgPrimary
    }

    let disclosureImageView: UIImageView = create { view in
        view.contentMode = .center
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(title: String, isUnlocked: Bool) {
        titleLabel.text = title
        disclosureImageView.image = isUnlocked ? .tattooFamilyDisclosure : .tattooLock
    }

    func setupLayout() {
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(4)
            make.leading.equalToSuperview().inset(16)
        }

        addSubview(disclosureImageView)
        disclosureImageView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalTo(titleLabel.snp.trailing).offset(12)
            make.trailing.equalToSuperview().inset(8)
            make.width.height.equalTo(48)
            make.top.equalToSuperview().priority(.medium)
        }
    }
}
