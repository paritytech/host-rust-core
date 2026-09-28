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
    let drawing: PocketCardDrawing

    init(card: PocketCardViewModel, drawing: PocketCardDrawing? = nil) {
        self.card = card
        self.drawing = drawing ?? .current(for: card.key.productId)
    }

    @State private var streamed: CustomMessageWidgetNode?

    private let resolver = WidgetDesignTokenResolver()

    var body: some View {
        PocketProductCardView(
            title: card.title,
            face: streamed ?? card.face,
            resolveImage: drawing.images.map { images in WidgetImageResolver { await images.resolve($0) } },
            onAction: { action, value in send(action, value) }
        )
        // Keyed on the Pocket as well as the card: a session that installed a
        // new one ended the stream this card was drawing, and a key of its own
        // id alone would never start another.
        .task(id: drawing.key(for: card.id)) { await draw() }
    }

    private func draw() async {
        guard let faces = drawing.faces else {
            Logger.shared.warning("[pocket] no face source yet; \(card.key.cardId.value) draws what is kept")
            return
        }

        for await face in faces.faces(for: card.key) {
            streamed = face.toWidgetNode(resolver: resolver)
        }
    }

    /// A press carries no payload; a text edit carries the new value as UTF-8,
    /// which is the shape every host sends.
    private func send(_ action: String, _ value: String?) {
        drawing.faces?.send(action: action, payload: Data((value ?? "").utf8), for: card.key)
    }
}
