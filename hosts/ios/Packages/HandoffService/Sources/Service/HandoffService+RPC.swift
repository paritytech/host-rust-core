import Foundation
import SubstrateSdk

enum RPCMethod {
    static let submit = "hop_submit"
    static let claim = "hop_claim"
    static let ack = "hop_ack"
    static let bitswapGet = "bitswap_v1_get"
}

enum HOPErrorCode {
    static let notFound = 1_004
}

enum BitswapErrorCode {
    static let invalidCid = -32_602
    static let notFound = -32_810
}
