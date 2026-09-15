import Foundation

extension People.RegisteredData {
    var displayLiteUsername: String {
        liteUsername.value
    }

    var suggestedFullUsername: String {
        liteUsername.partialUsername
    }
}
