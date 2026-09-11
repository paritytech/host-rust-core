import UIKit
import UIKit_iOS
import PolkadotUI

final class AssetView: RoundedView {
    let imageView: UIImageView = .init()

    var prefererredSize: CGFloat = 40 {
        didSet {
            cornerRadius = prefererredSize / 2

            invalidateIntrinsicContentSize()
        }
    }

    var iconSize: CGFloat = 32 {
        didSet {
            applyImageLayout()
        }
    }

    var iconCornerRadus: CGFloat?

    private var iconViewModel: ImageViewModelProtocol?

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: prefererredSize, height: prefererredSize)
    }

    private func applyImageLayout() {
        imageView.snp.remakeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGSize(width: iconSize, height: iconSize))
        }
    }

    private func setupLayout() {
        applyBackgroundStyle(with: prefererredSize / 2.0)

        addSubview(imageView)
        applyImageLayout()
    }

    func bind(viewModel: AssetView.ViewModel) {
        fillColor = viewModel.color
        highlightedFillColor = viewModel.color

        iconViewModel?.cancel(on: imageView)
        iconViewModel = viewModel.icon

        if let iconCornerRadus {
            iconViewModel?.loadImage(
                on: imageView,
                targetSize: CGSize(width: iconSize, height: iconSize),
                cornerRadius: iconCornerRadus,
                animated: true
            )
        } else {
            iconViewModel?.loadImage(
                on: imageView,
                targetSize: CGSize(width: iconSize, height: iconSize),
                animated: true
            )
        }
    }
}

extension AssetView {
    struct ViewModel {
        let color: UIColor
        let icon: ImageViewModelProtocol?
    }
}
