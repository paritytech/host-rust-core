import Foundation
import Products
import StructuredConcurrency
import TrUAPIHost
import UIKitExt

/// Rust chat runtime: the chat half of a product's worker.
///
/// The worker itself belongs to ``TrUAPIWorkerSupervisor``. The core keeps one
/// Worker execution per product and the reference ledger decides when it runs,
/// so a chat session takes one reference for as long as it is open rather than
/// opening an execution of its own — the same worker also draws the product's
/// Pocket cards.
///
/// Chat-environment seams route through that execution: user messages and
/// events publish chat actions, widget rendering streams typed renderer nodes,
/// and the product's chat surface serves the core's chat callbacks.
///
/// An actor so `start`/`dispose` never race on runtime state. Actors are
/// reentrant, so `dispose()` can interleave while `start` is suspended:
/// `dispose` flips `disposed` before its first await and `start` re-checks it
/// after every await, releasing anything it took in the gap.
actor ChatRustRuntime: ChatRuntimeProtocol {
    enum ChatSeamError: Error, Equatable {
        case notStarted
        /// The core normalizes room ids on the way back and rejects an empty one, so a
        /// chat with no room would reach the product as a message it cannot answer.
        case roomlessChat
        /// The stored message carries no product-defined type, so no
        /// `RenderContext` can name the body the action came from.
        case untypedBody
    }

    private let productId: ProductId
    private let workers: any TrUAPIWorkerSupervising
    private let references: @Sendable () throws -> any TrUAPIWorkerReferencing
    /// The product's own chat surface and routers, which outlive any one worker.
    private let seams: TrUAPIWorkerSeams
    private let workerStartupWindow: Duration
    private let renderStartupWindow: Duration
    private let logger: LoggerProtocol

    /// Held while this session's reference is out, so dispose gives back
    /// exactly what start took and never more.
    private var reference: (any TrUAPIWorkerReferencing)?
    private var roomsForwardingTask: Task<Void, Never>?
    private var started = false
    private var disposed = false

    init(
        productId: ProductId,
        workers: any TrUAPIWorkerSupervising,
        references: @Sendable @escaping () throws -> any TrUAPIWorkerReferencing,
        workerStartupWindow: Duration = .seconds(30),
        renderStartupWindow: Duration = .seconds(5),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.productId = productId
        self.workers = workers
        self.references = references
        self.workerStartupWindow = workerStartupWindow
        self.renderStartupWindow = renderStartupWindow
        self.logger = logger
        seams = workers.seams(of: productId)
    }

    deinit {
        // Locals first: assert's and &&'s autoclosures are nonisolated;
        // direct reads of the (Sendable) stored properties are only legal
        // in the deinit body itself.
        let started = started
        let disposed = disposed
        assert(!started || disposed, "ChatRustRuntime dropped without dispose()")
    }

    func start(messagingSupport: ProductsNativeApi.MessagingSupport) async throws {
        guard !started, !disposed else { throw CancellationError() }
        started = true

        do {
            try await startRuntime(messagingSupport: messagingSupport)
        } catch {
            // Nothing upstream tears us down — `ProductBot` only logs — so a
            // half-started session would hold its worker reference forever.
            await dispose()
            throw error
        }
    }

    func onUserMessage(text: String, roomId: String?) async throws {
        try checkNotDisposed()
        guard let roomId else { throw ChatSeamError.roomlessChat }
        try requireExecution().publishChatAction(HostChatActionSubscribeItem(
            roomId: roomId,
            peer: "native",
            payload: .messagePosted(.text(text: text))
        ))
    }

    func renderMessage(
        roomId: String?,
        messageId: String,
        messageType: String,
        messageData: Data
    ) async -> AsyncThrowingStream<ChatRendererOutput, Error> {
        do {
            guard let roomId else { throw ChatSeamError.roomlessChat }
            let nodes = try await renderNodesWhenConnected(
                deadline: ContinuousClock.now + renderStartupWindow,
                roomId: roomId,
                messageId: messageId,
                messageType: messageType,
                messageData: messageData
            )
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await node in nodes {
                            continuation.yield(.native(node))
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    /// A press inside a body the product drew is a renderer action addressed by
    /// `RenderContext`, not a chat action: `ChatActionPayload.actionTriggered`
    /// means a host-drawn `Actions` button, which this host does not raise.
    func dispatchEvent(
        roomId: String?,
        messageId: String,
        messageType: String?,
        actionId: String,
        payload: String?
    ) async {
        do {
            try checkNotDisposed()
            guard let roomId else { throw ChatSeamError.roomlessChat }
            // The core routes by context, so an action whose body we cannot name
            // would be delivered nowhere. Only this runtime needs the type: the
            // native one addresses by message id.
            guard let messageType else { throw ChatSeamError.untypedBody }
            try requireExecution().publishRendererAction(HostRendererActionSubscribeItem(
                context: .chatMessage(
                    roomId: roomId,
                    messageId: messageId,
                    messageType: messageType
                ),
                actionId: actionId,
                payload: payload.map { Data($0.utf8) } ?? Data()
            ))
        } catch is CancellationError {
            logger.debug("Rust chat runtime disposed before event \(actionId)")
        } catch {
            logger.error("Rust chat runtime failed to dispatch event \(actionId): \(error)")
        }
    }

    @MainActor
    func attach(presentationView view: ControllerBackedProtocol) {
        seams.routers.setPresentationView(view)
    }

    func dispose() async {
        guard !disposed else { return }
        // Flipped before the first suspension: any start resuming after this
        // point observes it and unwinds.
        disposed = true

        roomsForwardingTask?.cancel()
        roomsForwardingTask = nil

        // The core keeps the bridge, and the bridge keeps the surface: unbinding
        // is what releases the chat context.
        seams.chat.unbind()

        // A release, not a close. The product's cards may still hold the same
        // worker, and the core stops it once the last reference goes.
        reference?.releaseWorker(productId: productId)
        reference = nil

        logger.debug("Rust chat runtime disposed for: \(productId)")
    }
}

private extension ChatRustRuntime {
    func startRuntime(
        messagingSupport: ProductsNativeApi.MessagingSupport
    ) async throws {
        // Bound before the reference is taken, so the core can never reach a
        // surface with no binding.
        seams.chat.bind(messagingSupport)

        let reference = try references()
        reference.acquireWorker(productId: productId)
        self.reference = reference

        try await awaitWorker()
        try checkNotDisposed()
        startRoomsForwarding()

        logger.debug("Rust chat runtime started for: \(productId)")
    }

    /// `start` returns once the worker is up, because everything the bot does
    /// next — its welcome message first of all — is published through the
    /// execution.
    func awaitWorker() async throws {
        try await withTimeout(workerStartupWindow) { [workers, productId] in
            for try await execution in workers.executions(of: productId) where execution != nil {
                return
            }
            throw ChatSeamError.notStarted
        }
    }

    func checkNotDisposed() throws {
        guard !disposed else { throw CancellationError() }
    }

    /// A persisted message can decode before the product attaches. `ProductMessageDecoder`
    /// never evicts, so failing once breaks that cell for the session.
    func renderNodesWhenConnected(
        deadline: ContinuousClock.Instant,
        roomId: String,
        messageId: String,
        messageType: String,
        messageData: Data
    ) async throws -> AsyncThrowingStream<RendererNode, Error> {
        let request = ProductRendererRenderRequest(
            context: .chatMessage(
                roomId: roomId,
                messageId: messageId,
                messageType: messageType
            ),
            payload: messageData
        )

        while true {
            try checkNotDisposed()
            do {
                return try requireExecution().render(request)
            } catch let error where error.isTransientRenderStartupError {
                guard ContinuousClock.now < deadline else {
                    logger.error("Custom render gave up waiting for the product: \(messageId)")
                    throw error
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }
    }

    func requireExecution() throws -> TrUAPIProductExecutionProtocol {
        guard let execution = workers.currentExecution(of: productId) else {
            throw ChatSeamError.notStarted
        }
        return execution
    }

    /// Mirror the native room list into the core so product-side
    /// `chat.listSubscribe` sees native changes as they happen. The execution is
    /// read each time rather than captured, so a worker that restarts under this
    /// session keeps being told.
    func startRoomsForwarding() {
        roomsForwardingTask = Task { [logger, workers, productId, chat = seams.chat] in
            do {
                for try await rooms in try await chat.subscribeRooms() {
                    guard !Task.isCancelled else { return }
                    workers.currentExecution(of: productId)?
                        .notifyChatRoomsChanged(rooms: rooms.map { $0.toChatRoom() })
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Rust chat runtime rooms forwarding ended: \(error)")
            }
        }
    }
}

private extension Error {
    /// A cell can render before the worker is up (`notStarted`) or before the
    /// product attaches (`NotConnected`); the retry waits both out. Everything
    /// else surfaces at once. Only covers synchronous throws — a failure
    /// delivered inside the node stream never reaches here.
    var isTransientRenderStartupError: Bool {
        if (self as? ProductRuntimeError) == .NotConnected { return true }
        return (self as? ChatRustRuntime.ChatSeamError) == .notStarted
    }
}
