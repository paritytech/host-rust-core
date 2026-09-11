import SwiftUI
import DesignSystem
import ExternalAccessibility

public struct GameStateView: View, Hashable {
    private let viewModel: GameStateViewModel

    public init(viewModel: GameStateViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 8) {
            framedCard
                .accessibilityId(cardAccessibilityId)
            externalContentView
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var cardAccessibilityId: (any AccessibilityIdentifying)? {
        switch viewModel.state {
        case .register:
            AccessibilityID.Game.registerMessage
        case .registered,
             .starting:
            nil
        }
    }

    @ViewBuilder
    private var framedCard: some View {
        if viewModel.isMember {
            memberCard
                .prizesGlowingBorder(color: prizesGlowColor, cornerRadius: 16)
        } else {
            cardContent
                .background(
                    Self.prizesCardBackgroundColor,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .prizesGlowingBorder(color: prizesGlowColor, cornerRadius: 16)
        }
    }

    private var memberCard: some View {
        VStack(spacing: 0) {
            membershipHeaderText
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)

            cardContent
                .background(Self.prizesCardBackgroundColor, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(memberHeaderBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private var membershipHeaderText: some View {
        Text(.Game.gameInfoPlayToRetainMembership)
            .font(.system(size: 14, weight: .semibold))
            .tracking(0.28)
            .foregroundStyle(Color(.textAndIconsPrimaryDark))
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
    }

    private var memberHeaderBackground: LinearGradient {
        LinearGradient(
            colors: [prizesGlowColor, prizesGlowColor.opacity(0.75)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cardContent: some View {
        VStack(spacing: 8) {
            topLabelView
            mainContentView
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }

    private static let prizesCardBackgroundColor = Color(.gameInfoCardBackground)

    private var prizesGlowColor: Color {
        switch viewModel.state {
        case .register:
            Color(.prizesGlowRegister)
        case .registered:
            Color(.prizesGlowRegistered)
        case .starting:
            Color(.prizesGlowStarting)
        }
    }

    // MARK: - Subviews

    private var topLabelView: some View {
        Text(.Game.gameInfoNextGameStarting)
            .font(.titleMulish18Black())
            .tracking(0.36)
            .foregroundStyle(Color(.textAndIconsPrimaryDark))
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var mainContentView: some View {
        switch viewModel.state {
        case let .starting(gameDate):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(viewModel.timeRemaining(until: gameDate, from: context.date))
                    .font(.titleMulish32ExtraBlack())
                    .monospacedDigit()
                    .foregroundStyle(Color(.textAndIconsPrimaryDark))
                    .multilineTextAlignment(.center)
            }

        case let .register(date),
             let .registered(date):
            Text(viewModel.formattedDateString(from: date))
                .font(.titleMulish32ExtraBlack())
                .foregroundStyle(Color(.textAndIconsPrimaryDark))
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var externalContentView: some View {
        switch viewModel.state {
        case .register:
            registerButton

        case .registered,
             .starting:
            EmptyView()
        }
    }

    @ViewBuilder
    private var registerButton: some View {
        let isEnabled = viewModel.isRegisterEnabled
        let configuration = LoadableButtonConfiguration(
            isLoading: viewModel.isLoading,
            isEnabled: isEnabled
        )
        LoadableButton(
            configuration: configuration,
            action: viewModel.onRegister
        ) {
            Group {
                if isEnabled {
                    Text(.Game.gameInfoRegisterAction)
                } else {
                    Text(.Game.gameInfoRegisterOpeningSoon)
                }
            }
            .font(.buttonMulishExtraBlack())
            .tracking(0.44)
            .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.27))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(
            isEnabled
                ? AnyButtonStyle(GameGradientButtonStyle())
                : AnyButtonStyle(GameDisabledButtonStyle())
        )
        .accessibilityId(AccessibilityID.Game.registerButton)
    }
}

private struct GameGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(.prizesButtonBlueStart),
                        Color(.prizesButtonBlueMiddle),
                        Color(.prizesButtonBlueEnd)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .shadow(color: Color(.prizesButtonBlueShadow).opacity(0.6), radius: 16, y: 0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

private struct GameDisabledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .background(
                Color(.prizesButtonDisabledBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.95 : 1.0)
    }
}

private struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView

    init(_ style: some ButtonStyle) {
        _makeBody = { config in AnyView(style.makeBody(configuration: config)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}

private extension View {
    func prizesGlowingBorder(color: Color, cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(color.opacity(0.85), lineWidth: 8)
                .blur(radius: 16)
                .padding(-4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(color, lineWidth: 8)
        )
    }
}

// MARK: - 4. Preview

#if DEBUG
    final class CountdownFmt: CountdownDateFormatting {
        func formatWithSinglePart(to date: Date) -> String {
            date.debugDescription
        }

        func formatWithMultipleParts(to date: Date) -> String {
            date.debugDescription
        }

        func formatCompact(to date: Date) -> String {
            date.debugDescription
        }
    }

    #Preview("Normal") {
        ScrollView {
            VStack(spacing: 40) {
                let futureDate = Date().addingTimeInterval(3_600)
                let soonDate = Date().addingTimeInterval(90)
                GameStateView(viewModel: GameStateViewModel(
                    state: .register(gameDate: futureDate),
                    countdownFormatter: CountdownFmt()
                ))

                GameStateView(viewModel: GameStateViewModel(
                    state: .registered(gameDate: futureDate),
                    countdownFormatter: CountdownFmt()
                ))

                GameStateView(viewModel: GameStateViewModel(
                    state: .starting(gameDate: soonDate),
                    countdownFormatter: CountdownFmt()
                ))
            }
            .padding()
        }
        .background(Color(.backgroundPrimary))
    }

    #Preview("Loading") {
        ScrollView {
            VStack(spacing: 40) {
                let futureDate = Date().addingTimeInterval(3_600)
                let soonDate = Date().addingTimeInterval(90)
                GameStateView(viewModel: GameStateViewModel(
                    state: .register(gameDate: futureDate),
                    isLoading: true,
                    countdownFormatter: CountdownFmt()
                ))

                GameStateView(viewModel: GameStateViewModel(
                    state: .registered(gameDate: futureDate),
                    isLoading: true,
                    countdownFormatter: CountdownFmt()
                ))

                GameStateView(viewModel: GameStateViewModel(
                    state: .starting(gameDate: soonDate),
                    isLoading: true,
                    countdownFormatter: CountdownFmt()
                ))
            }
            .padding()
        }
        .background(Color(.backgroundPrimary))
    }
#endif
