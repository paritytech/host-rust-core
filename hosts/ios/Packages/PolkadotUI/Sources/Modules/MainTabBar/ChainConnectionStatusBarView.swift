import SwiftUI

public struct ChainConnectionStatusBarView: View, Hashable {
    public static let preferredHeight: CGFloat = 20

    public let models: [ChainConnectionStatusViewModel]

    public init(models: [ChainConnectionStatusViewModel]) {
        self.models = models
    }

    public var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(models) { viewModel in
                ChainStatusRingView(viewModel: viewModel)
            }
        }
        .safeAreaPadding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.preferredHeight)
    }
}
