import DesignSystem
import UIKit
import PolkadotUI
import SnapKit

final class GameViewController: ChatViewController {
    private static let fixedTheme = ThemesRegistry.default

    override func viewDidLoad() {
        super.viewDidLoad()

        traitOverrides.appTheme = Self.fixedTheme
        applyPrizesBackground()
        navigationBarController.setPinnedTitle(
            String(localized: .WeeklyGame.polkadotPrizesChatName)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.traitOverrides.appTheme = Self.fixedTheme
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.traitOverrides.remove(DSThemeTrait.self)
    }
}

private extension GameViewController {
    func applyPrizesBackground() {
        rootView.backgroundColor = .clear
        let backgroundView = PolkadotPrizesBackgroundView()
        rootView.insertSubview(backgroundView, at: 0)
        backgroundView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }
}
