import UIKit
import PolkadotUI

final class GameReportHeaderView: UICollectionReusableView {
    static let identifier = "GameReportHeaderView"

    private let titleLabel: UILabel = create {
        $0.numberOfLines = 2
        $0.attributedText = LabelStyle.headlineMulishXL().attributedString(
            from: String(localized: .Game.gameReportTitle),
            textColor: .fgPrimary,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
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

private extension GameReportHeaderView {
    func setupLayout() {
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints {
            $0.top.bottom.equalToSuperview()
            $0.leading.trailing.equalToSuperview()
        }
    }
}
