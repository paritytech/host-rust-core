import Foundation
import Products
import AsyncExtensions
import Testing
@testable import polkadot_app

struct DotNsPocketArchiveTests {
    @Test
    func readsAFaceOutOfTheWorkerArchive() async throws {
        let root = try makeArchive(files: ["faces/loyalty.json": "{}"])
        let archive = DotNsPocketArchive(dotNsResolver: StubResolver(root: root))

        let data = try await archive.file(
            contentId: "worker.game.paseo",
            path: "faces/loyalty.json",
            maxBytes: PocketPreviewLoader.maxBytes
        )

        #expect(String(decoding: data, as: UTF8.self) == "{}")
    }

    /// The preview path comes from a manifest anyone can publish, so it must not
    /// be able to name a file outside the archive it belongs to.
    @Test
    func refusesAPathThatClimbsOutOfTheArchive() async throws {
        let root = try makeArchive(files: ["faces/loyalty.json": "{}"])
        try Data("secret".utf8).write(to: root.deletingLastPathComponent().appending(path: "outside.json"))
        let archive = DotNsPocketArchive(dotNsResolver: StubResolver(root: root))

        await #expect(throws: (any Error).self) {
            try await archive.file(contentId: "worker.game.paseo", path: "../outside.json", maxBytes: 1_024)
        }
    }

    /// A lookalike sibling is not inside the archive. `..` is refused outright,
    /// so this never reaches the path comparison — which is the point: the
    /// comparison alone would have to get the directory boundary exactly right.
    @Test
    func refusesASiblingDirectoryWhoseNameStartsWithTheArchives() async throws {
        let root = try makeArchive(files: ["faces/loyalty.json": "{}"])
        let sibling = root.deletingLastPathComponent().appending(path: "content.staging")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: sibling.appending(path: "secret.json"))
        let archive = DotNsPocketArchive(dotNsResolver: StubResolver(root: root))

        await #expect(throws: (any Error).self) {
            try await archive.file(
                contentId: "worker.game.paseo",
                path: "../content.staging/secret.json",
                maxBytes: 1_024
            )
        }
    }

    /// The archive's own contents are written by the product, so a link planted
    /// inside it is as much the product's word as the path is.
    @Test
    func refusesALinkInsideTheArchiveThatPointsOutOfIt() async throws {
        let root = try makeArchive(files: ["faces/loyalty.json": "{}"])
        let outside = root.deletingLastPathComponent().appending(path: "outside.json")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "faces/escape.json"),
            withDestinationURL: outside
        )
        let archive = DotNsPocketArchive(dotNsResolver: StubResolver(root: root))

        await #expect(throws: (any Error).self) {
            try await archive.file(contentId: "worker.game.paseo", path: "faces/escape.json", maxBytes: 1_024)
        }
    }

    /// The face is read before the user has approved anything, so its weight is
    /// the product's choice. Refusing it once it is already resident would let a
    /// product publishing a large preview decide what the host allocates.
    @Test
    func stopsReadingAFileOnceItPassesTheBound() async throws {
        let root = try makeArchive(files: ["faces/big.json": String(repeating: "x", count: 8_192)])
        let archive = DotNsPocketArchive(dotNsResolver: StubResolver(root: root))

        let refusal = await #expect(throws: PocketPreviewError.self) {
            try await archive.file(contentId: "worker.game.paseo", path: "faces/big.json", maxBytes: 1_024)
        }

        guard case let .tooLarge(bytes) = refusal else {
            Issue.record("expected a size refusal, got \(String(describing: refusal))")
            return
        }
        // One byte past the bound is all that was ever held.
        #expect(bytes == 1_025)
    }
}

private func makeArchive(files: [String: String]) throws -> URL {
    let root = URL.temporaryDirectory
        .appending(path: "pocket-archive-\(UUID().uuidString)")
        .appending(path: "content")
    for (path, contents) in files {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: file)
    }
    return root
}

private struct StubResolver: DotNsResolverProtocol {
    let root: URL

    func resolveToLocalURL(dotNsName _: String) async throws -> URL { root }
    func getMetadataEntry(dotNsName _: String, key _: String) async throws -> String? { nil }
    func progressStream(dotNsName _: String) -> AnyAsyncSequence<DotNsLoadProgress> {
        AsyncStream<DotNsLoadProgress> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func clearCache() throws {}
}
