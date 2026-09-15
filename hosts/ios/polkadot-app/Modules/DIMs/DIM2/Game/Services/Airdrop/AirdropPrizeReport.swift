import Foundation

struct AirdropPrizeReport {
    let prizeUsd: Decimal
    let userTicket: String
    let winningTickets: [String]
    let ticketDistance: Int
    let totalEntries: Int
    let drawTime: UInt64
    let won: Bool
}
