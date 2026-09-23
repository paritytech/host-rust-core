import PolkadotUI
import SwiftUI

/// What the user is asked to approve: the card as it will look, and who backs it.
///
/// The face shown here is the one the host keeps for the card, so approving is
/// consent to this card rather than to whatever the product draws next.
///
/// Who backs it is named twice: the product's own display name, and the dotNS
/// name the host resolved it to. Only the second is the host's word, and it is
/// what tells two products apart when both claim to be the same one.
struct PocketAddCardView: View {
    /// The card is a fixed frame, so the sheet is too: it does not resize under
    /// the user between loading the offer and showing it.
    static let sheetHeight: CGFloat = 430

    @State var viewModel: PocketAddCardViewModel

    var body: some View {
        VStack(spacing: 24) {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(height: PocketCardSize.height)
            case let .offered(offer, face):
                header(productName: offer.productName, productId: offer.key.productId)
                PocketProductCardView(title: offer.title, face: face)
                actions
            case let .refused(message):
                refusal(message)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: Self.sheetHeight, alignment: .top)
        .background(Color(.bgSurfaceMain))
        .task { await viewModel.load() }
    }

    private func header(productName: String, productId: String) -> some View {
        VStack(spacing: 4) {
            Text(String(localized: .pocketAddCardTitle))
                .textStyle(.title24SemiBold())
                .foregroundStyle(Color(.fgPrimary))
                .padding(.bottom, 4)
            // Held to one line so a long name cannot push the dotNS name below
            // it out of the sheet.
            Text(productName)
                .textStyle(.body14Regular())
                .foregroundStyle(Color(.fgSecondary))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(productId)
                .textStyle(.caption12Regular())
                .foregroundStyle(Color(.fgTertiary))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
    }

    private func refusal(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .textStyle(.body16Regular())
                .foregroundStyle(Color(.fgSecondary))
                .multilineTextAlignment(.center)
            Button(String(localized: .pocketAddCardCancel)) { viewModel.onFinish() }
                .buttonStyle(.bordered)
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(String(localized: .pocketAddCardCancel)) { viewModel.onFinish() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isAdding)

            Button {
                Task { await viewModel.add() }
            } label: {
                if viewModel.isAdding {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(String(localized: .pocketAddCardConfirm))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isAdding)
        }
    }
}
