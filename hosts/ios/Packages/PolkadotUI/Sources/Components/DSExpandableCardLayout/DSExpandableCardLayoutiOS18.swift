import SwiftUI
import UIKit.UIApplication

@available(iOS 18, *)
struct DSExpandableCardLayoutiOS18<Card: View, Details: View>: View {
    private let isExpanded: Bool
    private let onCollapse: (() -> Void)?
    private let card: () -> Card
    private let details: () -> Details

    @State private var headerHeight: CGFloat = 0
    @State private var scrollOffsetY: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var containerHeight: CGFloat = 0

    private let maxBlur: CGFloat = 12

    init(
        isExpanded: Bool,
        onCollapse: (() -> Void)? = nil,
        @ViewBuilder card: @escaping () -> Card,
        @ViewBuilder details: @escaping () -> Details
    ) {
        self.isExpanded = isExpanded
        self.onCollapse = onCollapse
        self.card = card
        self.details = details
    }

    private var dragRange: CGFloat {
        if #available(iOS 26, *) {
            max(containerHeight / 4, 1)
        } else {
            max(containerHeight / 6, 1)
        }
    }

    private var dragProgress: CGFloat {
        guard dragRange > 0 else { return 0 }
        return min(max(dragOffset / dragRange, 0), 1)
    }

    private var internalBodyBlurRadius: CGFloat { dragProgress * maxBlur }
    private var internalBodyOpacity: Double { 1 - dragProgress }
    private var headerStickyThreshold: CGFloat { containerHeight }

    private var collapseGestureEnabled: Bool {
        isExpanded && scrollOffsetY < containerHeight / 3
    }

    private var collapseGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { _ in
                let shouldCollapse = dragOffset > dragRange
                withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
                    dragOffset = 0
                }
                if shouldCollapse { onCollapse?() }
            }
    }

    private var headerStickyOffset: CGFloat {
        -min(max(scrollOffsetY, 0), headerStickyThreshold)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                ScrollView(.vertical) {
                    details()
                }
                .contentMargins(.top, headerHeight + 16 + dragOffset)
                .blur(radius: internalBodyBlurRadius)
                .opacity(internalBodyOpacity)
                .onScrollGeometryChange(for: CGFloat.self) { proxy in
                    proxy.contentOffset.y + proxy.contentInsets.top
                } action: { _, newValue in
                    scrollOffsetY = newValue
                }
            }

            card()
                .offset(y: isExpanded ? headerStickyOffset + dragOffset : 0)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { headerHeight = $0 }
                .gesture(collapseGesture, isEnabled: collapseGestureEnabled)
//                .allowsHitTesting(isExpanded ? headerStickyOffset > -(headerHeight / 3) : true)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { containerHeight = Self.screenHeight }
    }

    private static var screenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
            .first ?? 0
    }
}
