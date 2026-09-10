import Foundation

public struct InstructionItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let detail: String

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}
