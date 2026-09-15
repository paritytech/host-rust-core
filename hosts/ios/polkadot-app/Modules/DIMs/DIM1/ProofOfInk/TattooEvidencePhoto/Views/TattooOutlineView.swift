import UIKit
import PolkadotUI
import DesignSystem

final class TattooOutlineView: UIView {
    private let lightImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)

    private let scrollView = UIScrollView()
    private var lineViews: [UIView] = []
    private var zeroDegreeCircleView: UIView!
    private let tattooImageView = UIImageView()
    private let degreesLabel = Label()

    private var lastFeedbackIndex: Int?

    private var isSetup = false
    private var currentRotationDegrees: CGFloat = 0 {
        didSet {
            updateForRotation()
        }
    }

    private let circleVisibilityOffset: CGFloat = 10
    private let degreeIncrement: CGFloat = 5
    private let bolderLineDegreeSpacing: CGFloat = 30
    private let maxRotationDegrees: CGFloat = 180
    private let lineSpacing: CGFloat = 11
    private let imageSize: CGFloat = 150

    private var imageViewModel: ImageViewModelProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !isSetup {
            isSetup = true
            // Center the content initially
            let centerOffsetX = (scrollView.contentSize.width - scrollView.bounds.width) / 2
            scrollView.contentOffset = CGPoint(x: centerOffsetX, y: 0)
            prepareHapticFeedback()
        }
    }

    func bind(viewModel: ImageViewModelProtocol?) {
        imageViewModel?.cancel(on: tattooImageView)
        imageViewModel = viewModel

        imageViewModel?.loadImage(
            on: tattooImageView,
            targetSize: CGSize(width: imageSize, height: imageSize),
            animated: true,
            completion: nil
        )
    }
}

extension TattooOutlineView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let contentWidth = scrollView.contentSize.width - scrollView.bounds.width
        let centerOffsetX = contentWidth / 2
        let normalizedOffset = scrollView.contentOffset.x - centerOffsetX
        let rawDegrees = normalizedOffset / centerOffsetX * maxRotationDegrees
        let clampedDegrees = max(-maxRotationDegrees, min(maxRotationDegrees, rawDegrees))
        let centralLineIndex = Int(round((scrollView.contentOffset.x + scrollView.bounds.width / 2) / lineSpacing))

        currentRotationDegrees = clampedDegrees
        if scrollView.isDragging || scrollView.isDecelerating {
            triggerHapticFeedback(scrollView, centralLineIndex: centralLineIndex)
        }
        animateLineSizes(scrollView, centralLineIndex: centralLineIndex)
    }
}

private extension TattooOutlineView {
    func animateLineSizes(_: UIScrollView, centralLineIndex: Int) {
        lineViews.enumerated().forEach { index, lineView in
            let scaleFactor: CGFloat =
                if index == centralLineIndex {
                    3.0
                } else if abs(centralLineIndex - index) == 1 {
                    2.0
                } else {
                    1.0
                }
            UIView.animate(withDuration: 0.1) {
                lineView.transform = CGAffineTransform(scaleX: 1.0, y: scaleFactor)
            }
        }
    }

    func triggerHapticFeedback(_: UIScrollView, centralLineIndex: Int) {
        guard centralLineIndex != lastFeedbackIndex else { return }
        let isBolderLine = centralLineIndex % (30 / Int(degreeIncrement)) == 0 ||
            centralLineIndex == 0 ||
            centralLineIndex == Int(maxRotationDegrees / degreeIncrement)

        if isBolderLine {
            heavyImpactFeedbackGenerator.impactOccurred()
        } else {
            lightImpactFeedbackGenerator.impactOccurred()
        }
        lastFeedbackIndex = centralLineIndex
    }

    func updateForRotation() {
        tattooImageView.transform = CGAffineTransform(rotationAngle: currentRotationDegrees * (.pi / 180))
        degreesLabel.text = "\(Int(currentRotationDegrees))°"
        zeroDegreeCircleView.isHidden = (-circleVisibilityOffset ... circleVisibilityOffset)
            .contains(currentRotationDegrees)
    }
}

// MARK: - Setup

private extension TattooOutlineView {
    func prepareHapticFeedback() {
        lightImpactFeedbackGenerator.prepare()
        heavyImpactFeedbackGenerator.prepare()
    }

    func setupScrollView() {
        scrollView.bounces = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
    }

    func setupLines() {
        let totalLines = Int((maxRotationDegrees * 2.0) / degreeIncrement) + 1 // Plus one for the 0 degree line
        let contentWidth = lineSpacing * CGFloat(totalLines - 1)
        scrollView.contentSize = CGSize(width: contentWidth, height: scrollView.frame.height)

        for index in 0 ..< totalLines {
            let lineView = UIView()
            scrollView.addSubview(lineView)
            lineViews.append(lineView)

            lineView.snp.makeConstraints { make in
                make.height.equalTo(10)
                make.centerY.equalTo(scrollView)
                make.leading.equalTo(scrollView.snp.leading).offset(CGFloat(index) * lineSpacing)
            }

            let isBoldLine = index % Int(bolderLineDegreeSpacing / degreeIncrement) == 0
            lineView.backgroundColor = isBoldLine ? .textAndIconsPrimaryDark :
                .textAndIconsTertiaryDark
            lineView.snp.makeConstraints { make in
                make.width.equalTo(isBoldLine ? 2 : 1)
            }

            if index == totalLines / 2 {
                zeroDegreeCircleView = prepareCircleView(above: lineView)
            }
        }
    }

    func prepareCircleView(above lineView: UIView) -> UIView {
        let circleView = UIView()
        circleView.backgroundColor = .textAndIconsPrimaryDark
        circleView.layer.cornerRadius = 3
        lineView.addSubview(circleView)
        circleView.snp.makeConstraints { make in
            make.width.height.equalTo(6)
            make.centerX.equalTo(lineView)
            make.bottom.equalTo(lineView.snp.top).offset(-4)
        }
        return circleView
    }

    func setupViews() {
        setupScrollView()
        setupLines()
        addSubview(tattooImageView)
        addSubview(degreesLabel)
        addSubview(scrollView)

        tattooImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        degreesLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview().offset(2)
            make.bottom.equalTo(scrollView.snp.top).offset(-8)
        }
        degreesLabel.typography = .paragraphLarge
        degreesLabel.textColor = .white100
        scrollView.snp.makeConstraints { make in
            make.bottom.equalToSuperview().offset(-8)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(30)
        }
    }
}
