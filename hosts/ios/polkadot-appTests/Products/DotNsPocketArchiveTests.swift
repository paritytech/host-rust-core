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

        let data = try await archive.file(contentId: "worker.game.paseo", path: "faces/loyalty.json")

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
            try await archive.file(contentId: "worker.game.paseo", path: "../outside.json")
        }
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
