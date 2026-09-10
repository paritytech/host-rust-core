import Foundation
import PolkadotUI

struct ChatMessageDecodingContext {
    let messageId: String
    let identifier: String
    let processAction: (Chat.Action) -> Void
}

protocol ChatMessageCustomDecoding {
    var identifier: MessageDecoderIdentifier { get }
    func decode(data: Data, context: ChatMessageDecodingContext) -> [any HashableContentConfiguration]
    func previewString(data: Data) -> String
}
