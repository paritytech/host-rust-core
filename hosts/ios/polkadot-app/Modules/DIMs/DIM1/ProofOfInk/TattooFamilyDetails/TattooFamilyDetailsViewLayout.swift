import UIKit
import PolkadotUI
import UIKit_iOS

final class TattooFamilyDetailsViewLayout: UIView {
    let collectionView: UICollectionView = {
        let layout = TattooFamilyDetailsCollectionLayout.createLayout()
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)

        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupStyle()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupStyle() {
        backgroundColor = .bgSurfaceMain

        collectionView.backgroundColor = .clear
    }

    private func setupLayout() {
        addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
