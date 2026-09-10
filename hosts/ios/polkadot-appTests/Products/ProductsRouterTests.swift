import Testing
import UIKit
import UIKitExt
import Products
@testable import polkadot_app

@MainActor
struct ProductsRouterTests {
    private final class StubView: UIViewController, ControllerBackedProtocol {}

    @Test
    func notReadyUntilPresentationViewAttached() {
        let anchor = StubView()
        let router = ProductsRouter()

        #expect(!router.isReady)

        router.setPresentationView(anchor)

        #expect(router.isReady)
    }

    @Test
    func presentReturnsFalseWhenNoPresentationView() {
        let router = ProductsRouter()

        #expect(!router.present(view: StubView()))
    }

    @Test
    func presentReturnsTrueWhenAnchored() {
        let anchor = StubView()
        let router = ProductsRouter()
        router.setPresentationView(anchor)

        #expect(router.present(view: StubView()))
    }
}
