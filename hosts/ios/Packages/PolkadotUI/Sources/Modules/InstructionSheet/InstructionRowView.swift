import SwiftUI
import DesignSystem

public struct InstructionRowView: View {
    private let number: Int
    private let title: String
    private let detail: String

    public init(
        number: Int,
        title: String,
        detail: String
    ) {
        self.number = number
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            numberBadge
            contentStack
            Spacer(minLength: 0)
        }
    }

    private var numberBadge: some View {
        Text("\(number)")
            .typography(.titleSmall)
            .foregroundStyle(Color(.textAndIconsSecondary))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.backgroundTertiary))
            )
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .typography(.titleMedium)
                .foregroundStyle(Color(.textAndIconsPrimaryDark))

            Text(detail)
                .typography(.paragraphLarge)
                .foregroundStyle(Color(.textAndIconsSecondary))
        }
    }
}

#Preview("Instruction Row") {
    ZStack {
        Color.black
            .ignoresSafeArea()

        VStack {
            InstructionRowView(
                number: 1,
                title: "Film During the Tattoo Session",
                detail: "Record the video while the tattoo is being executed, not before or after."
            )
            .padding()

            Divider()

            InstructionRowView(
                number: 2,
                title: "Show a Partially ",
                detail: "The tattoo must be in progress the stencil and the partially inked design must both be clearly visible."
            )
            .padding()
        }
    }
}
