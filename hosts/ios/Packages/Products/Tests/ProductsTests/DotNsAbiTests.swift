import Foundation
import SubstrateSdk
import Testing
import Web3Core
@testable import Products

struct DotNsAbiTests {
    @Test func encodeContentHashProducesCorrectSelector() throws {
        let node = try NameHash.nameHash("test.dot")
        let encoded = try DotNsAbi.encodeContentHash(node: node)

        // contenthash(bytes32) selector = 0xbc1c58d1
        #expect(encoded.prefix(4).toHex() == "bc1c58d1")
    }

    @Test func encodeContentHashIncludesNodeAsBytes32() throws {
        let node = try NameHash.nameHash("test.dot")
        let encoded = try DotNsAbi.encodeContentHash(node: node)

        // After 4-byte selector, next 32 bytes should be the node
        #expect(encoded.subdata(in: 4 ..< 36) == node)
    }

    @Test func encodeTextProducesCorrectSelector() throws {
        let node = try NameHash.nameHash("test.dot")
        let encoded = try DotNsAbi.encodeText(node: node, key: "manifest")

        // text(bytes32,string) selector = 0x59d1d43c
        #expect(encoded.prefix(4).toHex() == "59d1d43c")
    }

    @Test func decodeContentHashRoundTrips() throws {
        let originalHash = Data(0 ..< 34)
        let abiEncoded = try #require(abiEncodeBytes(originalHash))

        let decoded = DotNsAbi.decodeContentHash(output: abiEncoded)
        #expect(decoded == originalHash)
    }

    @Test func decodeContentHashReturnsNilForEmptyOutput() {
        let result = DotNsAbi.decodeContentHash(output: Data())
        #expect(result == nil)
    }

    @Test func decodeTextRoundTrips() throws {
        let abiEncoded = try #require(abiEncodeString("manifest-value"))

        let decoded = DotNsAbi.decodeText(output: abiEncoded)
        #expect(decoded == "manifest-value")
    }

    @Test func decodeTextReturnsNilForEmptyString() throws {
        let abiEncoded = try #require(abiEncodeString(""))

        let result = DotNsAbi.decodeText(output: abiEncoded)
        #expect(result == nil)
    }

    @Test func decodeResolverRoundTrips() throws {
        let address = Data(repeating: 0xAB, count: 20)
        let abiEncoded = try #require(abiEncodeAddress(address))

        #expect(DotNsAbi.decodeResolver(output: abiEncoded) == address)
    }

    /// How the registry reports a name it holds no entry for. Passing it on as a contract address
    /// would send every subsequent read to the zero account.
    @Test func decodeResolverReturnsNilForTheZeroAddress() throws {
        let abiEncoded = try #require(abiEncodeAddress(Data(repeating: 0, count: 20)))

        #expect(DotNsAbi.decodeResolver(output: abiEncoded) == nil)
    }

    @Test func decodeResolverReturnsNilForEmptyOutput() {
        #expect(DotNsAbi.decodeResolver(output: Data()) == nil)
    }
}

private func abiEncodeBytes(_ data: Data) -> Data? {
    ABIEncoder.encode(types: [.dynamicBytes], values: [data])
}

private func abiEncodeString(_ string: String) -> Data? {
    ABIEncoder.encode(types: [.string], values: [string])
}

private func abiEncodeAddress(_ address: Data) -> Data? {
    ABIEncoder.encode(types: [.address], values: [EthereumAddress(address)])
}
