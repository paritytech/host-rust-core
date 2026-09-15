import SwiftUI
import PolkadotUI

struct BalanceInfoView: View {
    var model: BalanceInfoModel?
    var onAvailableNowInfo: () -> Void = {}
    var onAvailableSoonInfo: () -> Void = {}

    var body: some View {
        if let model {
            VStack(alignment: .leading, spacing: 24) {
                titleSection
                cardSection(model: model)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 32)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.Transfer.balanceInfoTitle)
                .typography(.headlineSmall)
                .foregroundStyle(.fgPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(.Transfer.balanceInfoSubtitle)
                .typography(.paragraphLarge)
                .foregroundStyle(.fgPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cardSection(model: BalanceInfoModel) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            totalRow(model: model)
            availableNowSection(model: model)
            if model.availableSoon != nil {
                availableSoonSection(model: model)
            }
        }
        .padding(24)
        .background(.bgSurfaceNested, in: RoundedRectangle(cornerRadius: 24))
    }

    private func totalRow(model: BalanceInfoModel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(.Transfer.balanceInfoTotalTitle)
                    .typography(.titleMedium)
                    .foregroundStyle(.fgPrimary)
                Text(.Transfer.balanceInfoTotalSubtitle)
                    .typography(.bodyMedium)
                    .foregroundStyle(.fgSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(model.totalBalance)
                .typography(.titleMedium)
                .foregroundStyle(.fgPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func availableNowSection(model: BalanceInfoModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(.Transfer.balanceInfoAvailableNowTitle)
                        .typography(.titleMedium)
                        .foregroundStyle(.fgPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onAvailableNowInfo) {
                        Image(.iconInfo20)
                            .renderingMode(.template)
                            .foregroundStyle(.fgSecondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(model.availableNow)
                    .typography(.titleMedium)
                    .foregroundStyle(.fgPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(.Transfer.balanceInfoAvailableNowSubtitle)
                .typography(.bodyMedium)
                .foregroundStyle(.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                subRow(title: String(localized: .Transfer.balanceInfoSecured), amount: model.availablePrivate)
                subRow(title: String(localized: .Transfer.balanceInfoLowPrivacy), amount: model.gainingPrivacy)
            }
            .foregroundStyle(.fgSecondary)
        }
    }

    private func availableSoonSection(model: BalanceInfoModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(.Transfer.balanceInfoAvailableSoonTitle)
                        .typography(.titleMedium)
                        .foregroundStyle(.fgPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onAvailableSoonInfo) {
                        Image(.iconInfo20)
                            .renderingMode(.template)
                            .foregroundStyle(.fgTertiary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(model.availableSoon ?? "")
                    .typography(.titleMedium)
                    .foregroundStyle(.fgPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(.Transfer.balanceInfoAvailableSoonSubtitle)
                .typography(.bodyMedium)
                .foregroundStyle(.fgTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func subRow(title: String, amount: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .typography(.titleMedium)
            Spacer()
            Text(amount)
                .typography(.titleMedium)
        }
    }
}
