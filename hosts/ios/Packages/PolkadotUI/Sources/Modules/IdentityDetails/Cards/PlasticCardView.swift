import SwiftUI
import DesignSystem
import ExternalAccessibility

struct PlasticCardView: View {
    @State var viewModel: IdentityDetailsViewModelProtocol
    let isExpanded: Bool

    init(viewModel: IdentityDetailsViewModelProtocol, isExpanded: Bool = false) {
        _viewModel = State(initialValue: viewModel)
        self.isExpanded = isExpanded
    }

    var body: some View {
        ZStack(alignment: .center) {
            cardBackground
                .animation(.easeInOut, value: viewModel.isPersonal)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    cardIcon
                        .transition(.opacity)
                        .animation(.easeInOut, value: viewModel.isPersonal)

                    VStack(alignment: .leading, spacing: 4) {
                        if let username = viewModel.username {
                            Text(username.value)
                                .typography(.titleLarge)
                                .foregroundStyle(usernameColor)
                                .animation(.easeInOut, value: viewModel.isPersonal)
                                .accessibilityId(AccessibilityID.Wallet.usernameDisplay)
                        }

                        if viewModel.isRankVisible {
                            rankView
                        }
                    }

                    Spacer()
                    qrButton
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer()

                // TODO: not implemented for W3S
//                VStack(alignment: .leading, spacing: 8) {
//                    // TODO: use proper game count
//                    HStack(spacing: 5) {
//                        GameIndicatorView(filled: true)
//                        ForEach(0 ..< 5) { _ in
//                            GameIndicatorView()
//                        }
//                    }
//                    .shadow(color: .white, radius: 0.31874, x: 0, y: 0.50998)
//                    .shadow(color: Color(hex: 0xA0ABB3), radius: 0.1275, x: 0, y: -0.25499)
//
//                    Text(.Identity.gamesUntilMembership)
//                        .textStyle(.caption12Regular())
//                        .foregroundStyle(Color(hex: 0x808B93))
//                }
            }
            .padding(.vertical, DSSpacings.extraMedium)
            .padding(.horizontal, DSSpacings.mediumIncreased)
        }
        .bordered(
            cornerRadius: 24,
            gradient: LinearGradient(
                colors: [Color.white, Color(hex: 0x99A1AC)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private extension PlasticCardView {
    var qrButton: some View {
        Button {
            viewModel.onQrCode?()
        } label: {
            Image(.iconQrCode)
                .frame(width: 24, height: 24)
        }
        .padding(10)
        .disabled(isExpanded)
    }

    @ViewBuilder
    var cardIcon: some View {
        if viewModel.isPersonal {
            Image(.iconPlasticMember)
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .shadow(color: Color(red: 0.94, green: 0.93, blue: 0.93), radius: 0.5, x: 0, y: 1)
                .shadow(color: Color(red: 0.36, green: 0.34, blue: 0.4), radius: 0.25, x: 0, y: -0.5)
        } else {
            Image(.iconPlasticBasic)
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
        }
    }

    var rankView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(.Identity.rankTitle)
                .typography(.bodySmall)
                .foregroundStyle(rankLabelColor)

            Text(rankValueKey)
                .typography(.titleSmall)
                .foregroundStyle(rankValueColor)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: viewModel.isPersonal)
        }
    }

    var rankValueKey: LocalizedStringResource {
        viewModel.isPersonal ? .Identity.rankMember : .Identity.rankBasic
    }

    var usernameColor: Color {
        viewModel.isPersonal ? Color(hex: 0x0B0C0F) : Color(hex: 0x8C8F98)
    }

    var rankLabelColor: Color {
        viewModel.isPersonal ? Color(hex: 0x6F727A) : Color(hex: 0x8C8F98)
    }

    var rankValueColor: Color {
        viewModel.isPersonal ? Color(hex: 0x0B0C0F) : Color(hex: 0x8C8F98)
    }

    @ViewBuilder
    var cardBackground: some View {
        if viewModel.isPersonal {
            ZStack {
                Rectangle()
                    .motionFillingShader(shader: HolographicShaders.iridescentShine)

                HolographicWordmarkView(
                    image: .polkadotWordmarkShape,
                    widthRatio: 1.131,
                    verticalCenterRatio: 0.86,
                    aspectRatio: 420.362 / 90.5553
                )
            }
            .transition(.opacity)
        } else {
            RadialGradient(
                colors: [Color(hex: 0xDEDFE3), Color(hex: 0xBBBCC0)],
                center: .center,
                startRadius: 0,
                endRadius: 200
            )
            .transition(.opacity)
        }
    }
}

#Preview("Card") {
    let vm = IdentityDetailsViewModel()
    vm.username = IdentityDetailsUsernameViewModel(value: "cyberpink.89", isClaimed: true)

    let personVm = IdentityDetailsViewModel()
    personVm.username = vm.username
    personVm.isPersonal = true

    return ZStack {
        Color.black
        VStack {
            PlasticCardView(viewModel: vm)
                .cardAspectRatio()
                .padding()
            Button {
                personVm.isPersonal.toggle()
            } label: {
                Text("Toggle")
            }
            PlasticCardView(viewModel: personVm)
                .cardAspectRatio()
                .padding()
        }
    }
}
