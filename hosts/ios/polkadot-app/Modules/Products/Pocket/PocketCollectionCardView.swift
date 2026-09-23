import PolkadotUI
import Products
import SwiftUI

/// One card as the collection draws it: the face the host holds, replaced by
/// every face its product draws while the card is on screen.
///
/// Streaming here rather than on a screen of its own is what holds the worker
/// reference: the card is live for exactly as long as it is visible.
struct PocketCollectionCardView: View {
    let card: PocketCardViewModel
    var faces: (any PocketFaceSourcing)? = PocketWorkerFacade.shared.faces
    var images: PocketImageResolver?

    private var imageResolver: PocketImageResolver? {
        images ?? PocketWorkerFacade.shared.images(of: card.key.productId)
    }

    @State private var streamed: CustomMessageWidgetNode?

    private let resolver = WidgetDesignTokenResolver()

    var body: some View {
        PocketProductCardView(
            title: card.title,
            face: streamed ?? card.face,
            onAction: { action, value in send(action, value) },
            resolveImage: imageResolver.map { images in { await images.resolve($0) } }
        )
        .task(id: card.id) { await draw() }
    }

    private func draw() async {
        guard let faces else { return }

        for await face in faces.faces(for: card.key) {
            streamed = face.toWidgetNode(resolver: resolver)
        }
    }

    /// A press carries no payload; a text edit carries the new value as UTF-8,
    /// which is the shape every host sends.
    private func send(_ action: String, _ value: String?) {
        faces?.send(action: action, payload: Data((value ?? "").utf8), for: card.key)
    }
}
