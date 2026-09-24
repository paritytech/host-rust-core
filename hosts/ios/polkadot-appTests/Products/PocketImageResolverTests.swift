import Foundation
import AsyncExtensions
import PolkadotUI
import Products
import Testing
@testable import polkadot_app

/// Turns an image source inside a face into something the image loader can
/// fetch. A source that cannot be resolved answers nil: the rest of the face
/// still draws, with a hole where the image would be.
struct PocketImageResolverTests {
    @Test
    func resolvesAnArchiveImageToAFileInTheWorkersArchive() async throws {
        let root = try makeArchive(files: ["art/badge.png": "png"])
        let resolver = PocketImageResolver(
            contentId: { "worker.game.paseo" },
            dotNsResolver: StubResolver(root: root),
            ipfsUrl: { _ in nil }
        )

        let url = try #require(await resolver.resolve(.archive(path: "art/badge.png")))

        #expect(url.isFileURL)
        #expect(try Data(contentsOf: url) == Data("png".utf8))
    }

    /// The path comes from a face the product wrote, so it must not be able to
    /// name a file outside the archive it belongs to.
    @Test
    func refusesAnArchivePathThatClimbsOut() async throws {
        let root = try makeArchive(files: ["art/badge.png": "png"])
        try Data("secret".utf8).write(to: root.deletingLastPathComponent().appending(path: "outside.png"))
        let resolver = PocketImageResolver(
            contentId: { "worker.game.paseo" },
            dotNsResolver: StubResolver(root: root),
            ipfsUrl: { _ in nil }
        )

        #expect(await resolver.resolve(.archive(path: "../outside.png")) == nil)
    }

    /// A lookalike sibling is not inside the archive. `..` is refused outright,
    /// before any path comparison has to get the directory boundary right.
    @Test
    func refusesASiblingDirectoryWhoseNameStartsWithTheArchives() async throws {
        let root = try makeArchive(files: ["art/badge.png": "png"])
        let sibling = root.deletingLastPathComponent().appending(path: "content.staging")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: sibling.appending(path: "secret.png"))
        let resolver = PocketImageResolver(
            contentId: { "worker.game.paseo" },
            dotNsResolver: StubResolver(root: root),
            ipfsUrl: { _ in nil }
        )

        #expect(await resolver.resolve(.archive(path: "../content.staging/secret.png")) == nil)
    }

    @Test
    func resolvesABulletinImageToItsGatewayAddress() async throws {
        let resolver = PocketImageResolver(
            contentId: { "worker.game.paseo" },
            dotNsResolver: StubResolver(root: URL(fileURLWithPath: "/tmp/none")),
            ipfsUrl: { URL(string: "https://gateway.invalid/ipfs/\($0)") }
        )

        let url = try #require(await resolver.resolve(.bulletin(cid: "bafyimage")))

        #expect(url.absoluteString == "https://gateway.invalid/ipfs/bafyimage")
    }

    /// An archive that cannot be fetched leaves the rest of the face drawable.
    @Test
    func answersNoUrlWhenTheArchiveCannotBeRead() async {
        let resolver = PocketImageResolver(
            contentId: { "worker.game.paseo" },
            dotNsResolver: FailingResolver(),
            ipfsUrl: { _ in nil }
        )

        #expect(await resolver.resolve(.archive(path: "art/badge.png")) == nil)
    }
}

// MARK: - Fixtures

private func makeArchive(files: [String: String]) throws -> URL {
    let root = URL.temporaryDirectory
        .appending(path: "pocket-images-\(UUID().uuidString)")
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

private struct FailingResolver: DotNsResolverProtocol {
    func resolveToLocalURL(dotNsName: String) async throws -> URL {
        throw DotNsResolverError.resolutionFailed(dotNsName)
    }

    func getMetadataEntry(dotNsName _: String, key _: String) async throws -> String? { nil }
    func progressStream(dotNsName _: String) -> AnyAsyncSequence<DotNsLoadProgress> {
        AsyncStream<DotNsLoadProgress> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func clearCache() throws {}
}
