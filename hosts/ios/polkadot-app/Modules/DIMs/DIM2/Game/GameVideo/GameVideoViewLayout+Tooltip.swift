import UIKit
import UIKit_iOS

extension GameVideoViewLayout {
    func setupTooltip(viewModel: ViewModel) {
        guard let tooltipViewModel = viewModel.tooltipViewModel else {
            hideTooltip()
            return
        }
        guard currentTooltipModel != tooltipViewModel else {
            return
        }

        showTooltip(viewModel: tooltipViewModel)
    }

    func showTooltip(viewModel: GameVideoTooltipView.ViewModel) {
        currentTooltipModel = viewModel

        guard let currentTooltipView = currentTooltipView() else { return }

        currentTooltipView.bind(viewModel: viewModel)
        currentTooltipView.alpha = 0

        if currentTooltipView.superview == nil {
            addSubview(currentTooltipView)
        }

        switch viewModel {
        case .showGesture,
             .copyHost:
            currentTooltipView.snp.remakeConstraints {
                $0.centerX.equalTo(playersView.localPlayerView.snp.centerX)
                $0.bottom.equalTo(playersView.gridView.snp.top).offset(-3)
                $0.height.equalTo(63)
            }
        case .swipeHint:
            currentTooltipView.snp.remakeConstraints {
                $0.leading.trailing.equalToSuperview().inset(16)
                $0.centerY.equalTo(headerView.snp.centerY)
            }
        }

        tooltipAppearanceAnimator.animate(view: currentTooltipView, completionBlock: nil)

        tooltipTimer?.invalidate()
        tooltipTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: false
        ) { [weak self] _ in
            self?.dismissTooltip()
        }
    }

    func hideTooltip() {
        guard let currentTooltip = currentTooltipView() else { return }

        tooltipTimer?.invalidate()
        tooltipTimer = nil
        currentTooltipModel = nil

        currentTooltip.alpha = 0
        currentTooltip.removeFromSuperview()
    }

    func dismissTooltip() {
        guard
            let currentTooltipModel,
            let currentTooltip = currentTooltipView()
        else { return }

        tooltipTimer?.invalidate()
        tooltipTimer = nil

        tooltipDisappearanceAnimator.animate(view: currentTooltip) { [weak self] _ in
            currentTooltip.removeFromSuperview()
            self?.currentTooltipModel = nil
            self?.onTooltipDismissed?(currentTooltipModel)
        }
    }

    func currentTooltipView() -> GameVideoTooltipView? {
        guard let currentTooltipModel else { return nil }

        return switch currentTooltipModel {
        case .showGesture,
             .copyHost:
            playerTooltipView
        case .swipeHint:
            swipeTooltipView
        }
    }
}
