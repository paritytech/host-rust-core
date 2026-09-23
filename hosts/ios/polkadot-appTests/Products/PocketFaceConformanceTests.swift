import Foundation
import PolkadotUI
import TrUAPIHost
import Testing
@testable import polkadot_app

/// The faces a real product ships, decoded and drawn through the same path a
/// live face takes.
///
/// Both come from humanity-spa's `pocket:faces` and are checked against the
/// protocol on the product side, so a failure here is unambiguous: the defect
/// is this host's, not the file's.
///
/// Two of the five it writes: `devicehood` is the shape the other three share
/// node for node, and `candidate` is the large one. Keeping the identical three
/// would add pages of fixture and no coverage.
struct PocketFaceConformanceTests {
    private let decoder = RendererNodeJsonDecoder()

    @Test(arguments: ["devicehood", "candidate"])
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
