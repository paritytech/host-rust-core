import SwiftUI
import PolkadotUI

struct WalletView: View {
    @State var viewModel: WalletViewModelProtocol = WalletViewModel()
    @State private var viewHeight: CGFloat = 0
    private let collectiblesPeekHeight: CGFloat = 90
    @State private var scrollAtTop: Bool = true
    @Namespace private var cardNamespace
    private let peekHeight: CGFloat = 64

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                ZStack(alignment: .top) {
                    assetCard
                    identityCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height + proxy.safeAreaInsets.bottom
                } action: {
                    viewHeight = $0
                }
            }
        }
        .modifier(
            ConditionalOverlayModifier(
                available: viewModel.isCollectiblesAvailable,
                overlay: { collectiblesCard }
            )
        )
        .animation(.spring(duration: 0.45, bounce: 0.15), value: viewModel.expandedSection)
    }

    @ViewBuilder
    private var collectiblesCard: some View {
        CollectiblesCardView(
            isExpanded: viewModel.expandedSection == .collectiblesDetails,
            onViewCollectibles: { viewModel.onViewCollectibles?() }
        )
        .padding(.horizontal, 24)
        .frame(maxHeight: viewModel.expandedSection == .collectiblesDetails ? .infinity : nil)
        .alignmentGuide(.bottom) { dimensions in
            switch viewModel.expandedSection {
            case .none:
                dimensions[.top] + collectiblesPeekHeight
            case .collectiblesDetails:
                dimensions[.bottom]
            case .assetDetails,
                 .identityDetails:
                dimensions[.top] - offScreenOffset
            }
        }
        .opacity(collectiblesOpacity)
        .onTapGesture { viewModel.onCollectibles?() }
        .allowsHitTesting(collectiblesHitTest)
    }

    private var collectiblesOpacity: Double {
        switch viewModel.expandedSection {
        case .none,
             .collectiblesDetails:
            1
        case .assetDetails,
             .identityDetails:
            0
        }
    }

    private var collectiblesHitTest: Bool {
        switch viewModel.expandedSection {
        case .none,
             .collectiblesDetails:
            true
        case .assetDetails,
             .identityDetails:
            false
        }
    }

    @ViewBuilder
    private var identityCard: some View {
        IdentityDetailsViewLayout(
            viewModel: viewModel.identityDetailsViewModel,
            isExpanded: viewModel.expandedSection == .identityDetails,
            onCardTapped: { viewModel.onUsername?() },
            onCollapse: { viewModel.onCollapse?() }
        )
        .matchedGeometryEffect(id: "identity", in: cardNamespace)
        .scaleEffect(identityScale)
        .opacity(identityOpacity)
        .offset(y: identityOffsetY)
        .zIndex(identityZIndex)
        .allowsHitTesting(identityHitTest)
    }

    @ViewBuilder
    private var assetCard: some View {
        AssetDetailsView(
            viewModel: viewModel.assetDetailsViewModel,
            isExpanded: viewModel.expandedSection == .assetDetails,
            onCardTapped: {
                viewModel.onBalance?()
            },
            onCollapse: {
                viewModel.onCollapse?()
            }
        )
        .matchedGeometryEffect(id: "asset", in: cardNamespace)
        .scaleEffect(assetScale)
        .opacity(assetOpacity)
        .offset(y: assetOffsetY)
        .zIndex(assetZIndex)
        .allowsHitTesting(assetHitTest)
    }

    private var offScreenOffset: CGFloat {
        max(viewHeight, 1_000)
    }

    private var identityScale: CGFloat {
        1.0
    }

    private var identityOpacity: Double {
        switch viewModel.expandedSection {
        case .none,
             .identityDetails:
            1
        case .assetDetails,
             .collectiblesDetails:
            0
        }
    }

    private var identityOffsetY: CGFloat {
        switch viewModel.expandedSection {
        case .none:
            peekHeight
        case .identityDetails:
            0
        case .assetDetails:
            offScreenOffset
        case .collectiblesDetails:
            -offScreenOffset
        }
    }

    private var identityZIndex: Double {
        switch viewModel.expandedSection {
        case .none,
             .identityDetails:
            1
        case .assetDetails,
             .collectiblesDetails:
            0
        }
    }

    private var identityHitTest: Bool {
        switch viewModel.expandedSection {
        case .none,
             .identityDetails:
            true
        case .assetDetails,
             .collectiblesDetails:
            false
        }
    }

    private var assetScale: CGFloat {
        switch viewModel.expandedSection {
        case .none,
             .assetDetails:
            1.0
        case .identityDetails,
             .collectiblesDetails:
            0.95
        }
    }

    private var assetOpacity: Double {
        switch viewModel.expandedSection {
        case .none,
             .assetDetails:
            1
        case .identityDetails,
             .collectiblesDetails:
            0
        }
    }

    private var assetOffsetY: CGFloat {
        switch viewModel.expandedSection {
        case .none,
             .assetDetails,
             .identityDetails:
            0
        case .collectiblesDetails:
            -offScreenOffset
        }
    }

    private var assetZIndex: Double {
        switch viewModel.expandedSection {
        case .none:
            0
        case .assetDetails:
            2
        case .identityDetails,
             .collectiblesDetails:
            0
        }
    }

    private var assetHitTest: Bool {
        switch viewModel.expandedSection {
        case .none,
             .assetDetails:
            true
        case .identityDetails,
             .collectiblesDetails:
            false
        }
    }
}

private struct ConditionalOverlayModifier<V: View>: ViewModifier {
    let available: Bool
    let overlay: () -> V

    func body(content: Content) -> some View {
        if available {
            content
                .overlay(alignment: .bottom) {
                    overlay()
                }
        } else {
            content
        }
    }
}
