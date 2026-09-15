import UIKit
import SnapKit
import PolkadotUI

final class RootInitViewLayout: UIView {
    private let logoImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.tintColor = .fgPrimary
        return view
    }()

    private let issueView: TopBottomLabelView = {
        let view = TopBottomLabelView()
        view.topLabel.style = .title16SemiBold()
        view.topLabel.textColor = UIColor.fgPrimary
        view.topLabel.textAlignment = .center
        view.topLabel.numberOfLines = 0
        view.bottomLabel.style = .body14Regular()
        view.bottomLabel.textColor = UIColor.fgTertiary
        view.bottomLabel.textAlignment = .center
        view.bottomLabel.numberOfLines = 0
        view.spacing = 4
        view.isHidden = true
        return view
    }()

    private let stackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.alignment = .center
        view.spacing = 16
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .bgSurfaceMain
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension RootInitViewLayout {
    struct ViewModel {
        struct Issue {
            let title: String
            let subtitle: String
        }

        let logo: UIImage?
        let issue: Issue?
    }

    func bind(viewModel: ViewModel) {
        logoImageView.image = viewModel.logo

        guard let issue = viewModel.issue else {
            animateIssueDismissal()
            return
        }

        issueView.bind(viewModel: .init(top: issue.title, bottom: issue.subtitle))
        animateIssueAppearance()
    }
}

private extension RootInitViewLayout {
    func setupLayout() {
        addSubview(stackView)
        stackView.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.greaterThanOrEqualToSuperview().offset(16)
            $0.trailing.lessThanOrEqualToSuperview().offset(-16)
        }

        stackView.addArrangedSubview(logoImageView)
        stackView.addArrangedSubview(issueView)

        logoImageView.snp.makeConstraints {
            $0.size.equalTo(64)
        }
    }

    func animateIssueAppearance() {
        guard issueView.isHidden else { return }
        issueView.alpha = 0

        UIView.animate(springDuration: 0.3, bounce: 0) { [weak self] in
            self?.issueView.setHidden(false)
            self?.layoutIfNeeded()
        }

        UIView.animate(springDuration: 0.3, bounce: 0, delay: 0.25) { [issueView] in
            issueView.alpha = 1
        }
    }

    func animateIssueDismissal() {
        guard !issueView.isHidden else { return }

        UIView.animate(springDuration: 0.35, bounce: 0) { [weak self] in
            self?.issueView.alpha = 0
            self?.issueView.setHidden(true)
            self?.layoutIfNeeded()
        }
    }
}
