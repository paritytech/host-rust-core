import SwiftUI
import DesignSystem

public struct InstructionSheetView: View {
    public var viewModel: InstructionSheetViewModel

    public var onPrimaryAction: (() -> Void)?
    public var onCloseAction: (() -> Void)?

    public init(
        viewModel: InstructionSheetViewModel,
        onPrimaryAction: (() -> Void)? = nil,
        onCloseAction: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onPrimaryAction = onPrimaryAction
        self.onCloseAction = onCloseAction
    }

    public var body: some View {
        ZStack {
            Color(.backgroundPrimary)
            contentStack
        }
    }

    private var contentStack: some View {
        VStack(spacing: 0) {
            header
            scrollView
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                onCloseAction?()
            } label: {
                Image(.buttonClose)
            }
            .padding(.vertical, 6)
            .padding(.leading, 24)
            Spacer()
        }
    }

    private var scrollView: some View {
        ScrollView {
            headerSection
            instructionList
        }
        .contentMargins(.bottom, 40, for: .scrollContent)
    }

    private var headerSection: some View {
        VStack(spacing: 32) {
            RoundedRectangle(cornerSize: CGSize(width: 40, height: 40))
                .frame(width: 96, height: 96)
                .foregroundStyle(Color(.fill18))
                .overlay {
                    viewModel.glyphImage
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                }
            Text(viewModel.title)
                .typography(.headlineSmall)
                .multilineTextAlignment(.center)
        }
    }

    private var instructionList: some View {
        LazyVStack(spacing: 0) {
            let count = viewModel.items.count
            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                instructionRow(for: item, at: index)

                if index != count - 1 {
                    Divider()
                        .padding(.vertical, 16)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
    }

    private func instructionRow(for item: InstructionItem, at index: Int) -> some View {
        InstructionRowView(
            number: index + 1,
            title: item.title,
            detail: item.detail
        )
    }

    private var footer: some View {
        primaryButton
            .background {
                Color(.backgroundSecondary)
                    .ignoresSafeArea()
            }
    }

    private var primaryButton: some View {
        Button { onPrimaryAction?()
        } label: {
            Text(viewModel.primaryButtonTitle)
                .typography(.titleMedium)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.mainWhite)
        .padding(24)
    }
}

#Preview("Video Instructions") {
    let items: [InstructionItem] = [
        .init(
            title: "Film During the Tattoo Session",
            detail: "Record the video while the tattoo is being executed, not before or after."
        ),
        .init(
            title: "Film a Partially Completed Tattoo",
            detail: "The tattoo must be in progress—the stencil and the partially inked design must both be clearly visible."
        ),
        .init(
            title: "Use the In-App Camera",
            detail: "All footage must be recorded directly through the app's built-in camera."
        ),
        .init(
            title: "Record in One Continuous Take",
            detail: "Your video must be filmed without any pauses or cuts. If you stop, the recording will restart from the beginning."
        ),
        .init(
            title: "Choose Your Filming Style",
            detail: "You may film in any style you prefer, as long as the tattoo execution and the overall design are clearly shown."
        ),
        .init(
            title: "Get Assistance if Needed",
            detail: "You can ask someone to help you film, or record it yourself."
        )
    ]

    let viewModel = InstructionSheetViewModel(
        title: "Tattoo Documentation\nVideo Instructions",
        items: items,
        glyphImage: Image(systemName: "video.fill"),
        primaryButtonTitle: "Start Filming"
    )

    return InstructionSheetView(
        viewModel: viewModel,
        onPrimaryAction: {
            print("Start Filming tapped")
        }
    )
}

#Preview("Photo Instructions") {
    let items: [InstructionItem] = [
        .init(
            title: "Take the Photo During the Session",
            detail: "Capture the image while the work is in progress."
        ),
        .init(
            title: "Show Stencil + Ink",
            detail: "Both the stencil and partially completed ink must be visible."
        )
    ]

    let viewModel = InstructionSheetViewModel(
        title: "Documentation\nPhoto Instructions",
        items: items,
        glyphImage: Image(systemName: "camera.fill"),
        primaryButtonTitle: "Open Camera"
    )

    return InstructionSheetView(
        viewModel: viewModel,
        onPrimaryAction: {
            print("Open Camera tapped")
        }
    )
}
