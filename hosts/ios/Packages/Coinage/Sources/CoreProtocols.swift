import Foundation
import Individuality

public typealias PublicKey = Data
public typealias PrivateKey = Data

public typealias VoucherDerivationIndex = UInt32

public protocol PersonDataProtocol: Equatable {
    var personRecord: PeoplePallet.PersonRecord? { get }
    var ringPosition: MembersPallet.RingPosition? { get }
}
