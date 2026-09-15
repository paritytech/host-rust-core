import Foundation
import StatementStore
import Individuality

extension Game {
    struct Identifier {
        let index: GamePallet.GameIndex
    }
}

extension Game.Identifier: StatementFixedFieldConvertible {
    private static let contextData = Data("pop:game:tpc                ".utf8)

    func fixedStatementFieldData() throws -> Data {
        dataWithContext()
    }
}

extension Game.Identifier {
    func dataWithContext() -> Data {
        var data = Self.contextData
        withUnsafeBytes(of: index.bigEndian) {
            data.append(contentsOf: $0)
        }
        return data
    }
}
