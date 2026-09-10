import UIKit
import UIKit_iOS

struct TattooPhotoPreviewViewModel {
    let mainAction: String
    let photoPreview: UIImage
}

final class TattooPhotoPreviewViewLayout: UIView {
    let actionView: ConfirmView = create {
        $0.bind(state: .confirm)
        $0.actionButton.applyMainStyle()
    }

    private let photoPreview: UIImageView = .init()

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupStyle()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(viewModel: TattooPhotoPreviewViewModel) {
        actionView.actionButton.setTitle(viewModel.mainAction)
        photoPreview.image = viewModel.photoPreview
    }
}

private extension TattooPhotoPreviewViewLayout {
    func setupStyle() {
        backgroundColor = .black100
    }

    func setupLayout() {
        addSubview(photoPreview)
        photoPreview.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalToSuperview()
            make.height.equalTo(snp.width)
        }

        addSubview(actionView)
        actionView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-16)
            make.height.equalTo(UIConstants.actionHeight)
        }
    }
}
