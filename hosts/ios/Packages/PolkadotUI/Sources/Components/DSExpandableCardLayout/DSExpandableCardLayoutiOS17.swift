import SwiftUI
import UIKit

struct DSExpandableCardLayoutiOS17<Card: View, Details: View>: View {
    let isExpanded: Bool
    let onCollapse: (() -> Void)?
    let card: () -> Card
    let details: () -> Details

    @State private var headerHeight: CGFloat = 0
    @State private var scrollOffsetY: CGFloat = 0
    @State private var scrollReady = false
    @State private var dragOffset: CGFloat = 0
    @State private var containerHeight: CGFloat = 0

    private var dragRange: CGFloat { max(containerHeight / 6, 1) }

    private var dragProgress: CGFloat {
        guard dragRange > 0 else { return 0 }
        return min(max(dragOffset / dragRange, 0), 1)
    }

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

    private var collapseGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard isExpanded else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { _ in
                guard isExpanded else { return }
                let shouldCollapse = dragOffset > dragRange
                withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
                    dragOffset = 0
                }
                if shouldCollapse { onCollapse?() }
            }
    }

    private var headerStickyOffset: CGFloat {
        guard scrollReady else { return 0 }
        return -min(max(0, scrollOffsetY + headerHeight + 16), containerHeight)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                ScrollView(.vertical) {
                    GeometryReader {
                        Color.clear.preference(
                            key: ViewOffsetKey.self,
                            value: -$0.frame(in: .named("scroll")).origin.y
                        )
                    }
                    .frame(height: 1)
                    details()
                }
                .contentMargins(.top, headerHeight + 16 + dragOffset)
                .coordinateSpace(name: "scroll")
            }

            card()
                .offset(y: isExpanded ? headerStickyOffset + dragOffset : 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                .simultaneousGesture(collapseGesture)
                .allowsHitTesting(isExpanded ? headerStickyOffset > -(headerHeight / 3) : true)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { containerHeight = Self.screenHeight }
        .onPreferenceChange(ViewOffsetKey.self) {
            scrollOffsetY = $0
            scrollReady = true
        }
        .onChange(of: isExpanded) {
            dragOffset = 0
            scrollOffsetY = 0
            scrollReady = false
        }
    }

    private static var screenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
            .first ?? 0
    }
}

private struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}
