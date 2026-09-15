import SwiftUI
import ExternalAccessibility
import PolkadotUI
import DesignSystem

struct WalletBackupNotificationCard: View {
    let isUpdating: Bool

    var onSync: (() -> Void)?
    var onCancel: (() -> Void)?
    var onWhyUpdate: (() -> Void)?

    var body: some View {
        WalletCardContainer(
            color: Color.bgSurfaceContainer,
            contentPadding: 16
        ) {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .center, spacing: 16) {
            textContent
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                DSButton(
                    .Common.close,
                    style: .secondary,
                    expands: true
                ) {
                    onCancel?()
                }
                .accessibilityId(AccessibilityID.Wallet.backupNotificationCloseButton)
                DSButton(
                    .Common.update,
                    style: .primary,
                    expands: true
                ) {
                    onSync?()
                }
            }
            .disabled(isUpdating)
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(.BalanceSync.notificationTitle)
                    .typography(.titleLarge)
            } icon: {
                Image(.iconInfo20)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            .foregroundStyle(.fgWarning)

            Text(.BalanceSync.notificationDescription)
                .typography(.bodyMedium)
                .foregroundStyle(.fgPrimary)

            Button { onWhyUpdate?() } label: {
                HStack(spacing: 0) {
                    Text(.BalanceSync.notificationWhy)
                        .typography(.bodyMedium)
                    Image(.iconArrowRight20)
                        .renderingMode(.template)
                }
            }
            .foregroundStyle(.fgTertiary)
            .frame(height: 28)
        }
    }
}
