import SwiftUI

public final class InstructionSheetViewModel: ObservableObject {
    public let title: String
    public let items: [InstructionItem]
    public let glyphImage: Image
    public let primaryButtonTitle: String

    public init(
        title: String,
        items: [InstructionItem],
        glyphImage: Image,
        primaryButtonTitle: String
    ) {
        self.title = title
        self.items = items
        self.glyphImage = glyphImage
        self.primaryButtonTitle = primaryButtonTitle
    }
}
