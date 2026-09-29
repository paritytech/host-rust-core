import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

struct TattooCommitListViewModel {
    let tattooDescription: TopBottomLabelView.ViewModel
    let tattooImage: ImageViewModelProtocol?
}

final class TattooCommitViewLayout: ScrollableContainerLayoutView {
    let descriptionView: GenericBackgroundView<UIView> = .create { view in
        view.applyBackgroundStyle(.bgSurfaceContainer, cornerRadius: 32)
    }

    let tattooPreview: GenericBackgroundView<UIImageView> = .create { view in
        view.style = .roundedLargeLight
        view.wrappedView.contentMode = .scaleAspectFit
    }

    let descriptionLabelView: TopBottomLabelView = .create { view in
        view.setVerticalAndSpacing(8)
        view.stackView.isLayoutMarginsRelativeArrangement = true
        view.stackView.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)

        view.topLabel.typography = .headlineLarge
        view.topLabel.textColor = .fgPrimary
        view.topLabel.numberOfLines = 0

        view.bottomLabel.typography = .paragraphLarge
        view.bottomLabel.textColor = .fgPrimary
        view.bottomLabel.numberOfLines = 0
    }

    let loadableActionView: LoadableActionView = .create { view in
        view.applyMainStyle()
    }

    var actionButton: RoundedButton {
        loadableActionView.actionButton
    }

    private var imageViewModel: ImageViewModelProtocol?

    override func setupStyle() {
        super.setupStyle()

        backgroundColor = .bgSurfaceMain

        layoutInsets = UIEdgeInsets(
            top: 24,
            left: UIConstants.horizontalInsetShort,
            bottom: 28 + UIConstants.actionHeight + 8,
            right: UIConstants.horizontalInsetShort
        )
    }

    override func setupLayout() {
        super.setupLayout()

        containerView.respectsSafeArea = false

        loadableActionView.snp.makeConstraints { make in
            make.height.equalTo(UIConstants.actionHeight)
        }

        let descriptionContentView = UIView()

        descriptionContentView.addSubview(tattooPreview)
        tattooPreview.snp.makeConstraints {
            $0.leading.trailing.top.equalToSuperview()
        }

        descriptionContentView.addSubview(descriptionLabelView)
        descriptionLabelView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview()
            $0.top.equalTo(tattooPreview.snp.bottom)
        }

        descriptionContentView.addSubview(loadableActionView)
        loadableActionView.snp.makeConstraints {
            $0.leading.trailing.equalToSuperview().inset(16)
            $0.top.equalTo(descriptionLabelView.snp.bottom)
            $0.bottom.equalToSuperview().inset(24)
        }

        descriptionView.wrappedView.addSubview(descriptionContentView)
        descriptionContentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        addArrangedSubview(descriptionView, spacingAfter: 8)

        tattooPreview.wrappedView.snp.makeConstraints { make in
            make.width.equalTo(tattooPreview.wrappedView.snp.height)
        }
    }

    func bind(viewModel: TattooCommitListViewModel) {
        imageViewModel?.cancel(on: tattooPreview.wrappedView)

        imageViewModel = viewModel.tattooImage

        let width = UIScreen.main.bounds.width
        imageViewModel?.loadImage(
            on: tattooPreview.wrappedView,
            targetSize: CGSize(width: width, height: width),
            cornerRadius: 32,
            animated: true,
            completion: nil
        )

        descriptionLabelView.topLabel.text = viewModel.tattooDescription.top
        descriptionLabelView.bottomLabel.text = viewModel.tattooDescription.bottom
    }
}
