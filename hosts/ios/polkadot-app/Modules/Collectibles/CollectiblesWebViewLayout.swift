import SnapKit
import UIKit
import WebKit
import PolkadotUI

final class CollectiblesWebViewLayout: UIView {
    let webView: WKWebView
    let activityIndicatorView = ActivityIndicatorView()

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        backgroundColor = .backgroundPrimary
        webView.isOpaque = false
        webView.backgroundColor = .backgroundPrimary
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        addSubview(webView)
        webView.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom)
            make.leading.trailing.equalToSuperview()
        }

        addSubview(activityIndicatorView)
        activityIndicatorView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
