import PolkadotUI
import SnapKit
import UIKit

final class PolkadotPrizesNavTitlePill: UIView {
    private let label = UILabel()

    init(text: String) {
        super.init(frame: .zero)

        backgroundColor = UIColor(resource: .dim2StripeRest)
        layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        layer.borderWidth = 1

        label.font = .title18SemiBold()
        label.textColor = .white
        label.textAlignment = .center
        label.text = text

        addSubview(label)
        label.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(20)
            $0.top.bottom.equalToSuperview().inset(6)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
