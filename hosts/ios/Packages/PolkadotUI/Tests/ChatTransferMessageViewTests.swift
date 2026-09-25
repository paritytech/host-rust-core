import Testing
import UIKit
@testable import PolkadotUI

@MainActor
struct ChatTransferMessageViewTests {
    @Test("Without a remote logo the card draws the bundled mark tinted like the amount")
    func fallsBackToBundledMark() {
        let configuration = makeConfiguration(assetIcon: nil)
        let view = ChatTransferMessageView(configuration: configuration)

        let image = view.assetIconView.image
        #expect(image != nil)
        #expect(image?.renderingMode == .alwaysTemplate)
        #expect(view.assetIconView.isHidden == false)
        #expect(view.assetIconView.tintColor == configuration.amountTextColor)
    }

    @Test("A remote logo is drawn as delivered")
    func drawsRemoteLogo() {
        let remote = UIImage.solidRed
        let view = ChatTransferMessageView(configuration: makeConfiguration(assetIcon: remote))

        #expect(view.assetIconView.image === remote)
        #expect(view.assetIconView.isHidden == false)
    }

    @Test("Reapplying a configuration without a logo restores the bundled mark")
    func reappliedConfigurationRestoresMark() {
        let view = ChatTransferMessageView(configuration: makeConfiguration(assetIcon: .solidRed))

        view.configuration = makeConfiguration(assetIcon: nil)

        #expect(view.assetIconView.image?.renderingMode == .alwaysTemplate)
    }

    @Test("A short claim strikes the original amount through and warns that it differs")
    func partialClaimShowsOriginalAmount() {
        let configuration = makeConfiguration(assetIcon: nil, state: .outgoing(.claimed), originalAmountText: "50")
        let view = ChatTransferMessageView(configuration: configuration)

        #expect(view.originalAmountLabel.isHidden == false)
        #expect(view.originalAmountLabel.attributedText?.string == "50")
        #expect(view.subtitleLabel.text == String(localized: .transferStatusAmountDiffers))
        #expect(view.subtitleIconView.isHidden)
    }

    @Test("A failed transfer renders its status in the error tint")
    func failedRendersErrorTint() {
        let view = ChatTransferMessageView(configuration: makeConfiguration(assetIcon: nil, state: .incoming(.failed)))

        #expect(view.subtitleLabel.text == String(localized: .transferStatusError))
        #expect(view.subtitleLabel.textColor == .fgError)
        #expect(view.originalAmountLabel.isHidden)
    }
}

private extension ChatTransferMessageViewTests {
    func makeConfiguration(
        assetIcon: UIImage?,
        state: ChatTransferMessageConfiguration.DirectionalState = .outgoing(.sent),
        originalAmountText: String? = nil
    ) -> ChatTransferMessageConfiguration {
        ChatTransferMessageConfiguration(
            title: "You Sent",
            amountText: "20",
            tokenSymbol: "CASH",
            assetIcon: assetIcon,
            originalAmountText: originalAmountText,
            state: state,
            statusConfiguration: .init(
                dateFormatter: FixedTimestampFormatter(),
                date: .now,
                textColor: .fgPrimaryInverted,
                image: nil,
                isEdited: false
            ),
            backgroundColor: .bgSurfaceContainerInverted,
            titleColor: .fgPrimaryInverted,
            amountBackgroundColor: .bgSurfaceNestedInverted,
            amountTextColor: .fgPrimaryInverted,
            originalAmountTextColor: .fgSecondaryInverted,
            side: .trailing
        )
    }
}

private struct FixedTimestampFormatter: TimestampFormatting {
    func string(for _: Date, now _: Date) -> String { "2:33" }
}

private extension UIImage {
    static var solidRed: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
