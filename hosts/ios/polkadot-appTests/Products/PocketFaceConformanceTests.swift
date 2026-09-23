import Foundation
import PolkadotUI
import TrUAPIHost
import Testing
@testable import polkadot_app

/// The faces a real product ships, decoded and drawn through the same path a
/// live face takes.
///
/// These five come from humanity-spa's `pocket:faces`, and are checked against
/// the protocol on the product side. So they are the one fixture where a
/// failure is unambiguous: if one of them does not decode, the defect is this
/// host's, not the file's.
struct PocketFaceConformanceTests {
    private let decoder = RendererNodeJsonDecoder()

    @Test(arguments: ["devicehood", "candidate", "member", "caution", "suspended"])
    func decodesAndDrawsAPublishedFace(_ name: String) throws {
        let face = try decoder.decode(faceText(name))

        // Drawn as well as decoded: a tree the mapper drops would still decode.
        #expect(face.toWidgetNode(resolver: WidgetDesignTokenResolver()) != nil)
    }

    /// The bound the approval sheet applies, checked against the largest face a
    /// real product ships — so the limit is known to be above what products
    /// actually send rather than guessed.
    @Test
    func theLargestPublishedFaceFitsWellInsideTheSizeBound() throws {
        let bytes = try faceData("candidate").count

        #expect(bytes < PocketPreviewLoader.maxBytes / 2)
    }

    private func faceData(_ name: String) throws -> Data {
        let url = try #require(
            Bundle(for: FaceFixtures.self).url(forResource: name, withExtension: "json"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    private func faceText(_ name: String) throws -> String {
        try String(decoding: faceData(name), as: UTF8.self)
    }
}

private final class FaceFixtures {}
