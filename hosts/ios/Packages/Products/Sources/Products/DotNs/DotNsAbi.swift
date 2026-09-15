import Foundation
import Web3Core

public enum DotNsAbiError: Error {
    case encodingFailed(function: String)
}

public enum DotNsAbi {
    private enum Constants {
        static let evmAddressSize = 20
        static let zeroContractAddress = Data(repeating: 0, count: evmAddressSize)
    }

    // contenthash(bytes32 node) returns (bytes)
    private static let contenthashFunction = ABI.Element.Function(
        name: "contenthash",
        inputs: [.init(name: "node", type: .bytes(length: 32))],
        outputs: [.init(name: "", type: .dynamicBytes)],
        constant: true,
        payable: false
    )

    // text(bytes32 node, string key) returns (string)
    private static let textFunction = ABI.Element.Function(
        name: "text",
        inputs: [.init(name: "node", type: .bytes(length: 32)), .init(name: "key", type: .string)],
        outputs: [.init(name: "", type: .string)],
        constant: true,
        payable: false
    )

    // resolver(bytes32 node) returns (address) — on the name registry, not a resolver.
    private static let resolverFunction = ABI.Element.Function(
        name: "resolver",
        inputs: [.init(name: "node", type: .bytes(length: 32))],
        outputs: [.init(name: "", type: .address)],
        constant: true,
        payable: false
    )

    public static func encodeResolver(node: Data) throws -> Data {
        try encode(resolverFunction, parameters: [node])
    }

    /// Nil when the registry has no entry for the name, which it reports as the zero address.
    public static func decodeResolver(output: Data) -> Data? {
        let element = ABI.Element.function(resolverFunction)

        guard
            let decoded = element.decodeReturnData(output),
            let address = decoded["0"] as? EthereumAddress
        else {
            return nil
        }

        let bytes = address.addressData

        guard bytes.count == Constants.evmAddressSize, bytes != Constants.zeroContractAddress else {
            return nil
        }

        return bytes
    }

    public static func encodeContentHash(node: Data) throws -> Data {
        try encode(contenthashFunction, parameters: [node])
    }

    public static func decodeContentHash(output: Data) -> Data? {
        let element = ABI.Element.function(contenthashFunction)
        guard let decoded = element.decodeReturnData(output) else { return nil }
        return decoded["0"] as? Data
    }

    public static func encodeText(node: Data, key: String) throws -> Data {
        try encode(textFunction, parameters: [node, key])
    }

    public static func decodeText(output: Data) -> String? {
        let element = ABI.Element.function(textFunction)
        guard let decoded = element.decodeReturnData(output) else { return nil }
        let result = decoded["0"] as? String
        return result?.isEmpty == true ? nil : result
    }
}

private extension DotNsAbi {
    /// Encoding fails only on a parameter that does not match the signature, which would otherwise
    /// go on the wire as an empty call the contract answers with something unrelated.
    static func encode(_ function: ABI.Element.Function, parameters: [Any]) throws -> Data {
        guard let encoded = ABI.Element.function(function).encodeParameters(parameters) else {
            throw DotNsAbiError.encodingFailed(function: function.name ?? "unknown")
        }

        return encoded
    }
}
