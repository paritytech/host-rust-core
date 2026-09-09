import Foundation
import UIKit
import SnapKit

final class AttestationOverlayView: UIView {
    let leftArrowView = ScrubbableArrowView(type: .leftGreen)
    let rightArrowView = ScrubbableArrowView(type: .rightRed)

    let leftArrowDragIndicator = UIView()
    let rightArrowDragIndicator = UIView()

    // rounded overlay containers with colored border
    let positiveAttestationView = UIView()
    let negativeAttestationView = UIView()

    // half of view container responsible for gesture
    let leftArrowGestureContainerView = UIView()
    let rightArrowGestureContainerView = UIView()

    let decisionImageView: UIImageView = create {
        $0.isUserInteractionEnabled = false
        $0.contentMode = .scaleAspectFit
    }

    lazy var controller = AttestationOverlayController(view: self)

    var cornerRadius: CGFloat = 0 {
        didSet { updateCorners() }
    }

    override var isUserInteractionEnabled: Bool {
        didSet {
            isUserInteractionEnabledChanged()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        controller.overlayDidLayoutSubviews()
    }

    private func updateCorners() {
        clipsToBounds = true
        layer.cornerRadius = cornerRadius

        positiveAttestationView.clipsToBounds = true
        positiveAttestationView.layer.cornerRadius = cornerRadius

        negativeAttestationView.clipsToBounds = true
        negativeAttestationView.layer.cornerRadius = cornerRadius
    }

    private func isUserInteractionEnabledChanged() {
        controller.overlayDidChangeUserInteractionEnabled()
    }

    private func setupViews() {
        updateCorners()

        let borderWidth: CGFloat = 6
        let attestedColor: UIColor = .fgSuccess
        let notAttestedColor: UIColor = .fgError

        positiveAttestationView.layer.borderWidth = borderWidth
        positiveAttestationView.layer.borderColor = attestedColor.cgColor
        positiveAttestationView.backgroundColor = attestedColor.withAlphaComponent(0.16)

        negativeAttestationView.layer.borderWidth = borderWidth
        negativeAttestationView.layer.borderColor = notAttestedColor.cgColor
        negativeAttestationView.backgroundColor = notAttestedColor.withAlphaComponent(0.16)

        leftArrowDragIndicator.backgroundColor = attestedColor
        leftArrowDragIndicator.layer.cornerRadius = borderWidth / 2

        rightArrowDragIndicator.backgroundColor = notAttestedColor
        rightArrowDragIndicator.layer.cornerRadius = borderWidth / 2

        positiveAttestationView.isUserInteractionEnabled = false
        negativeAttestationView.isUserInteractionEnabled = false

        addSubview(leftArrowGestureContainerView)
        leftArrowGestureContainerView.snp.makeConstraints {
            $0.leading.top.bottom.equalToSuperview()
            $0.width.equalToSuperview().multipliedBy(0.5)
        }

        addSubview(rightArrowGestureContainerView)
        rightArrowGestureContainerView.snp.makeConstraints {
            $0.trailing.top.bottom.equalToSuperview()
            $0.width.equalToSuperview().multipliedBy(0.5)
        }

        leftArrowGestureContainerView.addSubview(leftArrowView)
        leftArrowView.snp.makeConstraints {
            $0.leading.equalToSuperview()
            $0.width.equalToSuperview().multipliedBy(0.9)
            $0.height.equalToSuperview().multipliedBy(0.3)
            $0.top.equalToSuperview().offset(16)
        }

        rightArrowGestureContainerView.addSubview(rightArrowView)
        rightArrowView.snp.makeConstraints {
            $0.trailing.equalToSuperview()
            $0.width.equalToSuperview().multipliedBy(0.9)
            $0.height.equalToSuperview().multipliedBy(0.3)
            $0.bottom.equalToSuperview().inset(16)
        }

        addSubview(leftArrowDragIndicator)
        leftArrowDragIndicator.snp.makeConstraints {
            $0.centerY.equalTo(leftArrowView.snp.centerY)
            $0.leading.equalToSuperview()
            $0.width.equalTo(6)
            $0.height.equalTo(leftArrowView.snp.height).multipliedBy(0.8)
        }

        addSubview(rightArrowDragIndicator)
        rightArrowDragIndicator.snp.makeConstraints {
            $0.centerY.equalTo(rightArrowView.snp.centerY)
            $0.trailing.equalToSuperview()
            $0.width.equalTo(6)
            $0.height.equalTo(rightArrowView.snp.height).multipliedBy(0.8)
        }

        addSubview(positiveAttestationView)
        positiveAttestationView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(negativeAttestationView)
        negativeAttestationView.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }

        addSubview(decisionImageView)
        decisionImageView.snp.makeConstraints {
            $0.edges.equalToSuperview().inset(36)
        }
    }
}

extension AttestationOverlayView {
    struct ViewModel {
        let attested: Bool?
        let uiAvailable: Bool
        let interactionsEnabled: Bool
        let dragHintEnabled: Bool
        let autoDiscardSpan: AnimationSpan?

        static var empty: ViewModel {
            ViewModel(
                attested: nil,
                uiAvailable: false,
                interactionsEnabled: false,
                dragHintEnabled: false,
                autoDiscardSpan: nil
            )
        }
    }

    func bind(
        viewModel: ViewModel,
        delegate: AttestationOverlayControllerDelegate?
    ) {
        controller.delegate = delegate
        controller.bind(attested: viewModel.attested)
        controller.bind(discardTiming: viewModel.autoDiscardSpan)

        isHidden = !viewModel.uiAvailable
        isUserInteractionEnabled = viewModel.interactionsEnabled

        if viewModel.dragHintEnabled {
            controller.restartBouncing()
        } else {
            controller.stopBouncing()
        }
    }

    func prepareForReuse() {
        bind(viewModel: .empty, delegate: nil)
    }
}
