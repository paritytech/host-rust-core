import Foundation

struct GameGroupSettings {
    let preferredMaxGroupSize: UInt
    let numberOfPlayers: UInt

    func getNumberOfGroups() -> UInt {
        guard numberOfPlayers > 0, preferredMaxGroupSize > 0 else {
            return 0
        }

        if numberOfPlayers % preferredMaxGroupSize == 0 {
            return numberOfPlayers / preferredMaxGroupSize
        } else {
            return (numberOfPlayers / preferredMaxGroupSize) + 1
        }
    }

    func getGroupsSizes() -> [UInt] {
        let numberOfGroups = getNumberOfGroups()

        return (0 ..< numberOfGroups).map { groupIndex in
            (0 ..< preferredMaxGroupSize).reduce(0) { accum, counterInGroup in
                let indexInGroup = groupIndex + counterInGroup * numberOfGroups

                return indexInGroup < numberOfPlayers ? accum + 1 : accum
            }
        }
    }

    func getMaxGroupSize() -> UInt {
        getGroupsSizes().max() ?? preferredMaxGroupSize
    }
}
