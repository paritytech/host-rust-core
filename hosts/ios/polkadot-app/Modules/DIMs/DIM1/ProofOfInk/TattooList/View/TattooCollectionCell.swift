import UIKit
import UIKit_iOS
import PolkadotUI

final class TattooCollectionCell: UICollectionViewCell {
    enum Constants {
        static let cornerRadius: CGFloat = 32
    }

    let roundedBackgroundView: RoundedView = .create { view in
        view.applyBackgroundStyle(.white100, cornerRadius: Constants.cornerRadius)
    }

    let imageView: UIImageView = .create { view in
        view.contentMode = .scaleAspectFill
    }

    private var calculatedSize: CGSize?

    private var imageViewModel: ImageViewModelProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyViewModel() {
        guard let calculatedSize else {
            return
        }

        imageViewModel?.cancel(on: imageView)
        imageViewModel?.loadImage(
            on: imageView,
            targetSize: calculatedSize,
            cornerRadius: Constants.cornerRadius,
            animated: true,
            completion: nil
        )
    }

    private func setupLayout() {
        contentView.addSubview(roundedBackgroundView)
        roundedBackgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.size != calculatedSize, bounds.size.width > 0, bounds.size.height > 0 {
            calculatedSize = bounds.size
            applyViewModel()
        }
    }

    func bind(viewModel: ImageViewModelProtocol?) {
        imageViewModel?.cancel(on: imageView)

        imageViewModel = viewModel

        applyViewModel()
    }
}
