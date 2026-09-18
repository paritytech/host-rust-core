import Foundation
import PolkadotUI
import Products

@Observable
final class ProductWidgetViewModel: WidgetNodeProviding {
    @MainActor private(set) var node: CustomMessageWidgetNode?

    private let messageId: String
    private let runtime: ChatRuntimeProtocol
    private let tokenResolver: any WidgetDesignTokenResolving
    private let logger: LoggerProtocol
    private var renderTask: Task<Void, Never>?

    init(
        roomId: String?,
        messageId: String,
        messageType: String,
        messageData: Data,
        runtime: ChatRuntimeProtocol,
        tokenResolver: any WidgetDesignTokenResolving,
        logger: LoggerProtocol
    ) {
        self.messageId = messageId
        self.runtime = runtime
        self.tokenResolver = tokenResolver
        self.logger = logger

        renderTask = Task { [weak self] in
            guard let self else { return }

            let stream = await runtime.renderMessage(
                roomId: roomId,
                messageId: messageId,
                messageType: messageType,
                messageData: messageData
            )

            do {
                for try await output in stream {
                    guard !Task.isCancelled else { return }

                    let resolved: CustomMessageWidgetNode? = switch output {
                    case let .scaleEncoded(hexString):
                        try ScaleWidget.decode(from: hexString)
                            .toWidgetNode(resolver: self.tokenResolver)
                    case let .native(node):
                        node.toWidgetNode(resolver: self.tokenResolver)
                    }
                    await MainActor.run { self.node = resolved }
                    #if targetEnvironment(simulator)
                        TrUAPIE2EMarkers.write("custom-renderer-update", logger: logger)
                    #endif
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Widget render stream failed for \(messageId): \(error)")
            }
        }
    }

    deinit {
        renderTask?.cancel()
    }
}
