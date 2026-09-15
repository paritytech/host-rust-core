import UIKit

extension GameVideoPlayersView {
    enum AnimationState: Equatable {
        case hidden
        case waiting
        case hostIntroduction
        case grid(GridState)
    }

    enum GridState {
        case gameplay
        case ended
    }

    enum AnimationDurations {
        static let gridDuration = 0.8
    }

    func setupAnimationState(with viewModel: GameVideoViewLayout.ViewModel) {
        let oldState = animationState
        animationState = makeAnimationState(viewModel: viewModel)
        hostPlayerView = hostPlayerView(with: viewModel)
        setupAnimationState(withOldState: oldState)
    }
}

private extension GameVideoPlayersView {
    func makeAnimationState(viewModel: GameVideoViewLayout.ViewModel) -> AnimationState {
        switch viewModel.state {
        case .waiting:
            .waiting
        case .hosting:
            .grid(.gameplay)
        case .hostingEnd:
            .grid(.ended)
        case .hostIntroduction:
            .hostIntroduction
        case .subroundStart:
            .hidden
        }
    }

    func setupAnimationState(withOldState oldState: AnimationState?) {
        guard shouldApplyChanges(fromOldState: oldState) else {
            return
        }

        if shouldAnimateFromGridToHostIntroduction(withOldState: oldState) {
            animateFromGridToHostIntroduction()
        } else if shouldAnimateFromHostIntroductionToGridGameplay(withOldState: oldState) {
            animateFromHostIntroductionToGridGameplay()
        } else if shouldApplyCurrentAnimationState(withOldState: oldState) {
            applyCurrentAnimationState()
        }
    }

    func shouldApplyChanges(fromOldState oldState: AnimationState?) -> Bool {
        guard let oldState else {
            return true
        }
        return oldState != animationState
    }

    func hostPlayerView(
        with viewModel: GameVideoViewLayout.ViewModel
    ) -> GameVideoPlayerItemView {
        guard
            let player = viewModel.orderedPlayers.first,
            player.isHost
        else {
            return localPlayerView
        }
        return remotePlayerViewsByAccountId[player.accountId]
            ?? localPlayerView
    }
}

// MARK: - Animations

private extension GameVideoPlayersView {
    func shouldAnimateFromGridToHostIntroduction(withOldState oldState: AnimationState?) -> Bool {
        guard case let .grid(oldGridState) = oldState else {
            return false
        }
        return oldGridState == .ended
            && animationState == .hostIntroduction
    }

    func shouldAnimateFromHostIntroductionToGridGameplay(withOldState oldState: AnimationState?) -> Bool {
        guard case let .grid(gridState) = animationState else {
            return false
        }
        return oldState == .hostIntroduction
            && gridState == .gameplay
    }

    func shouldApplyCurrentAnimationState(withOldState oldState: AnimationState?) -> Bool {
        guard
            case let .grid(oldGridState) = oldState,
            case let .grid(gridState) = animationState
        else {
            return true
        }
        return !(oldGridState == .gameplay && gridState == .ended)
    }

    func animateFromHostIntroductionToGridGameplay() {
        guard let hostPlayerView else {
            applyGridAnimationState(with: .gameplay)
            return
        }

        hostPlayerView.transform = .identity
        hostPlayerView.applyRegularStyle()
        layoutIfNeeded()
        let initialFrame = hostPlayerView.frame

        let otherViewsWithIndices = playerViewsForGrid.enumerated().compactMap { tuple in
            if tuple.element !== hostPlayerView {
                tuple
            } else {
                nil
            }
        }

        gridView.setItemsViews(otherViewsWithIndices)
        layoutIfNeeded()

        gridView.setItemsViews([(0, hostPlayerView)])
        layoutIfNeeded()
        hostPlayerView.transform = transform(
            from: initialFrame,
            to: hostPlayerView.frame
        )
        applyHostIntroductionViewsState(isVisible: false)
        otherViewsWithIndices.forEach { $0.element.alpha = 1 }

        UIView.animate(
            withDuration: AnimationDurations.gridDuration,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0,
            options: .curveEaseInOut,
            animations: {
                hostPlayerView.transform = .identity
            }
        )
    }

    func animateFromGridToHostIntroduction() {
        guard let hostPlayerView else {
            applyHostIntroductionAnimationState()
            return
        }

        hostPlayerView.transform = .identity
        hostPlayerView.applyHostIntroductionStyle()
        layoutIfNeeded()
        let initialFrame = hostPlayerView.frame

        let otherViews = playerViewsForGrid.compactMap { view in
            if view !== hostPlayerView {
                view
            } else {
                nil
            }
        }

        applyHostPlayerViewIntroductionConstraints()
        applyHostIntroductionViewsState(isVisible: true)
        layoutIfNeeded()
        hostPlayerView.transform = transform(
            from: initialFrame,
            to: hostPlayerView.frame
        )
        otherViews.forEach { $0.alpha = 0 }

        UIView.animate(
            withDuration: AnimationDurations.gridDuration,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0,
            options: .curveEaseInOut,
            animations: {
                hostPlayerView.transform = .identity
            }
        )
    }
}

// MARK: - Apply animation state

private extension GameVideoPlayersView {
    func applyCurrentAnimationState() {
        switch animationState {
        case .waiting:
            applyWaitingAnimationState()
        case .hostIntroduction:
            applyHostIntroductionAnimationState()
        case let .grid(gridState):
            applyGridAnimationState(with: gridState)
        case .hidden:
            break
        }
    }

    func applyWaitingAnimationState() {
        playerViewsForGrid.forEach { $0.alpha = 0 }
        applyHostIntroductionViewsState(isVisible: false)

        localPlayerView.alpha = 1
        localPlayerView.transform = .identity
        localPlayerView.snp.remakeConstraints {
            $0.edges.equalToSuperview()
        }
    }

    func applyHostIntroductionAnimationState() {
        playerViewsForGrid.forEach { $0.alpha = 0 }
        applyHostIntroductionViewsState(isVisible: true)

        if let hostPlayerView {
            hostPlayerView.transform = .identity
            hostPlayerView.applyHostIntroductionStyle()
            hostPlayerView.alpha = 1
            applyHostPlayerViewIntroductionConstraints()
        }
    }

    func applyHostPlayerViewIntroductionConstraints() {
        guard let hostPlayerView else {
            return
        }

        hostPlayerView.snp.remakeConstraints {
            $0.leading.trailing.equalToSuperview().inset(32)
            $0.centerY.equalToSuperview()
            $0.width.equalTo(hostPlayerView.snp.height)
        }
    }

    func applyGridAnimationState(with _: GridState) {
        let viewsWithIndices = playerViewsForGrid.enumerated().map { tuple in
            tuple.element.alpha = 1
            tuple.element.transform = .identity
            return tuple
        }
        gridView.setItemsViews(viewsWithIndices)
        applyHostIntroductionViewsState(isVisible: false)
    }
}

private extension GameVideoPlayersView {
    func transform(from initialFrame: CGRect, to finalFrame: CGRect) -> CGAffineTransform {
        guard finalFrame.width > 0, finalFrame.height > 0 else {
            return .identity
        }

        return CGAffineTransform(
            a: initialFrame.width / finalFrame.width,
            b: 0,
            c: 0,
            d: initialFrame.height / finalFrame.height,
            tx: initialFrame.midX - finalFrame.midX,
            ty: initialFrame.midY - finalFrame.midY
        )
    }
}

private extension GameVideoPlayersView {
    var hostIntroductionViews: [UIView] {
        [hostIntroductionTopView, hostIntroductionBottomView]
    }

    func applyHostIntroductionViewsState(isVisible: Bool) {
        hostIntroductionViews.forEach { view in
            if isVisible {
                if view.superview == nil {
                    addSubview(view)
                }
            } else {
                view.alpha = 0
                view.removeFromSuperview()
            }

            guard view.superview != nil else {
                return
            }

            view.alpha = 1
            applyHostIntroductionViewConstraints(view)
        }
    }

    func applyHostIntroductionViewConstraints(_ view: UIView) {
        guard let hostPlayerView, view.superview != nil else {
            return
        }

        let inset = -32

        view.snp.remakeConstraints {
            $0.leading.trailing.equalToSuperview()

            if view === hostIntroductionTopView {
                $0.bottom.equalTo(hostPlayerView.snp.top).inset(inset)
            } else {
                $0.top.equalTo(hostPlayerView.snp.bottom).inset(inset)
            }
        }
    }
}
