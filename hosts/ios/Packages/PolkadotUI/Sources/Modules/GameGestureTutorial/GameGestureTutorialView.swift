import SwiftUI
import DesignSystem

public struct GameGestureTutorialView: View {
    @State private var currentSegment: Int = 0
    @State private var dragOffset: CGFloat = 0

    public var onDoneTapped: () -> Void = {}

    public init(onDoneTapped: @escaping () -> Void = {}) {
        self.onDoneTapped = onDoneTapped
    }

    public var body: some View {
        VStack(spacing: 0) {
            pageIndicator
                .padding(.top, Constants.pageIndicatorTopPadding)

            segmentsContainer

            Spacer()

            actionButton
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.bottom, Constants.bottomPadding)
        }
        .contentShape(.rect)
        .gesture(swipeGesture)
        .background(Color(.backgroundPrimary))
    }
}

// MARK: - Computed properties

private extension GameGestureTutorialView {
    var firstSegmentOpacity: Double {
        if currentSegment == 0 {
            let leftSwipeOffset = abs(min(dragOffset, 0))
            let progress = Double(leftSwipeOffset) / Constants.fadeRange
            return max(0, 1.0 - progress)
        } else {
            let rightSwipeOffset = max(dragOffset, 0)
            let progress = Double(max(rightSwipeOffset - Constants.fadeRange, 0)) / Constants.fadeRange
            return min(1.0, progress)
        }
    }

    var secondSegmentOpacity: Double {
        if currentSegment == 1 {
            let progress = Double(max(dragOffset, 0)) / Constants.fadeRange
            return max(0, 1.0 - progress)
        } else {
            let leftSwipeOffset = abs(min(dragOffset, 0))
            let progress = Double(max(leftSwipeOffset - Constants.fadeRange, 0)) / Constants.fadeRange
            return min(1.0, progress)
        }
    }

    var firstSegmentOffset: CGFloat {
        if currentSegment == 0 {
            min(dragOffset, 0)
        } else {
            max(dragOffset, 0) - Constants.totalSwipeRange
        }
    }

    var secondSegmentOffset: CGFloat {
        if currentSegment == 1 {
            max(dragOffset, 0)
        } else {
            min(dragOffset, 0) + Constants.totalSwipeRange
        }
    }
}

// MARK: - Views

private extension GameGestureTutorialView {
    var pageIndicator: some View {
        HStack(spacing: Constants.pageIndicatorSpacing) {
            ForEach(0 ..< 2) { index in
                Circle()
                    .fill(
                        currentSegment == index
                            ? Color(.textAndIconsPrimaryDark)
                            : Color(.textAndIconsPrimaryDark).opacity(Constants.inactiveIndicatorOpacity)
                    )
                    .frame(width: Constants.pageIndicatorSize, height: Constants.pageIndicatorSize)
            }
        }
    }

    var segmentsContainer: some View {
        ZStack {
            makeSegment(
                title: .Game.tutorialFirstTitle,
                image: .imageGestureTutorial,
                imagePadding: Constants.horizontalPaddingImage1
            )
            .opacity(firstSegmentOpacity)
            .offset(x: firstSegmentOffset)

            makeSegment(
                title: .Game.tutorialSecondTitle,
                image: .imageGestureTutorialSwipe,
                imagePadding: 0
            )
            .opacity(secondSegmentOpacity)
            .offset(x: secondSegmentOffset)
        }
    }

    var actionButton: some View {
        Button(action: handleButtonTap) {
            Text(currentSegment == 0
                ? String(localized: .Game.tutorialNextButton)
                : String(localized: .Game.tutorialDoneButton))
                .typography(.titleMedium)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.mainWhite)
    }
}

// MARK: - View Factory

private extension GameGestureTutorialView {
    func makeSegment(title: LocalizedStringResource, image: ImageResource, imagePadding: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Text(title)
                .typography(.headlineLarge)
                .foregroundColor(Color(.textAndIconsPrimaryDark))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Constants.titleHorizontalPadding)
                .padding(.top, Constants.titleTopPadding)

            Image(image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(.horizontal, imagePadding)
                .padding(.top, Constants.imageTopPadding)
        }
    }
}

// MARK: - Gesture

private extension GameGestureTutorialView {
    var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                withAnimation(.easeInOut(duration: Constants.animationDuration)) {
                    if value.translation.width < -Constants.swipeThreshold, currentSegment == 0 {
                        currentSegment = 1
                    } else if value.translation.width > Constants.swipeThreshold, currentSegment == 1 {
                        currentSegment = 0
                    }
                    dragOffset = 0
                }
            }
    }
}

// MARK: - Handlers

private extension GameGestureTutorialView {
    func handleButtonTap() {
        if currentSegment == 0 {
            withAnimation(.smooth) {
                dragOffset = -Constants.totalSwipeRange
            } completion: {
                currentSegment = 1
                dragOffset = 0
            }
        } else {
            onDoneTapped()
        }
    }
}

// MARK: - Constants

private extension GameGestureTutorialView {
    enum Constants {
        static let fadeRange: CGFloat = 75.0
        static let totalSwipeRange: CGFloat = 150.0
        static let swipeThreshold: CGFloat = 50.0
        static let animationDuration: CGFloat = 0.3
        static let buttonAnimationDuration: CGFloat = 0.5

        static let pageIndicatorSize: CGFloat = 12.0
        static let pageIndicatorSpacing: CGFloat = 8.0
        static let pageIndicatorTopPadding: CGFloat = 16.0
        static let inactiveIndicatorOpacity: CGFloat = 0.4

        static let segmentSpacing: CGFloat = 24.0
        static let titleTopPadding: CGFloat = 42.0
        static let imageTopPadding: CGFloat = 200.0
        static let horizontalPaddingImage1: CGFloat = 60.0

        static let horizontalPadding: CGFloat = UIConstants.horizontalInsetMedium
        static let titleHorizontalPadding: CGFloat = UIConstants.horizontalInsetWide
        static let bottomPadding: CGFloat = 16.0
    }
}

#Preview {
    GameGestureTutorialView()
}
