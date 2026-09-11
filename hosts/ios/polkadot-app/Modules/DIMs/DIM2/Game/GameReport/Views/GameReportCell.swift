import UIKit
import UIKit_iOS
import PolkadotUI

final class GameReportCell: UICollectionViewCell {
    static let identifier = "GameReportCell"

    private let previewView: GenericBackgroundView<GameReportPreviewView> = create {
        $0.applyBackgroundStyle(.bgSurfaceContainer, cornerRadius: 24)
    }

    private let statusImageView: UIImageView = create {
        $0.contentMode = .scaleAspectFit
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

extension GameReportCell {
    func bind(gameVote: GameVote) {
        previewView.wrappedView.bind(gameVote: gameVote)

        statusImageView.image = gameVote.isPerson
            ? personStatusImage
            : notPersonStatusImage
    }
}

private extension GameReportCell {
    func setupLayout() {
        addSubview(previewView)
        previewView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(statusImageView)
        statusImageView.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.width.height.equalTo(56)
            $0.bottom.equalToSuperview().inset(16)
        }
    }

    var notPersonStatusImage: UIImage {
        .gameReportNotPerson
    }

    var personStatusImage: UIImage {
        .gameReportPerson
    }
}

final class GameReportPreviewView: UIView {
    private let previewImageView: UIImageView = create {
        $0.contentMode = .scaleAspectFill
        $0.layer.cornerRadius = 24
        $0.clipsToBounds = true
    }

    private let overlayView: UIView = create {
        $0.backgroundColor = .clear
        $0.layer.cornerRadius = 24
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

extension GameReportPreviewView {
    func bind(gameVote: GameVote) {
        if let imageData = gameVote.previewImageData {
            previewImageView.image = UIImage(data: imageData)
        } else {
            previewImageView.image = nil
        }

        overlayView.backgroundColor = gameVote.isPerson
            ? personOverlayColor
            : notPersonOverlayColor
    }
}

private extension GameReportPreviewView {
    func setupLayout() {
        addSubview(previewImageView)
        previewImageView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(overlayView)
        overlayView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
    }

    var notPersonOverlayColor: UIColor {
        .bgStatusError.withAlphaComponent(0.3)
    }

    var personOverlayColor: UIColor {
        .bgStatusSuccess.withAlphaComponent(0.16)
    }
}
