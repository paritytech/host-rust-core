import Foundation
import StatementStore

protocol OutgoingRequestSizeValidating {
    var maxPayloadSize: Int { get }
}

extension OutgoingRequestSizeValidating {
    func scaleEncodedPayloadFits(_ payload: Data) -> Bool {
        maxPayloadSize >= payload.count
    }
}

final class OutgoingRequestSizeValidator {
    let maxStatementSize: Int

    init(maxStatementSize: Int) {
        self.maxStatementSize = maxStatementSize
    }
}

extension OutgoingRequestSizeValidator: OutgoingRequestSizeValidating {
    var maxPayloadSize: Int {
        maxStatementSize - Constants.reservedSize
    }
}

private extension OutgoingRequestSizeValidator {
    enum Constants {
        static let scaleIndexSize = 1
        static let expirySize = 8
        static let proofSize = scaleIndexSize + StatementProof.signatureSize + StatementProof.signerSize
        static let channelSize = StatementFieldConstants.fixedFieldSize
        static let topicSize = StatementFieldConstants.fixedFieldSize

        static let reservedSize = scaleIndexSize + proofSize
            + scaleIndexSize + expirySize
            + scaleIndexSize + channelSize
            + scaleIndexSize + topicSize
            + scaleIndexSize
    }
}
