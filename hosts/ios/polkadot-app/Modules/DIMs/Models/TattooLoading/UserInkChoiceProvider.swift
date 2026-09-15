import Operation_iOS
import Keystore_iOS
import Foundation
import SubstrateSdk
import Individuality
import OperationExt

protocol UserInkChoiceProviding: AnyObject {
    func procedural(
        for familyIndex: ProofOfInkPallet.FamilyIndex,
        variantIndex: ProofOfInkPallet.VariantIndex,
        familyId: ProofOfInkPallet.FamilyId,
        entropy: Data?
    ) -> ProofOfInk.Choice?

    func proceduralAccount(
        for familyIndex: ProofOfInkPallet.FamilyIndex,
        familyId: ProofOfInkPallet.FamilyId,
        accountId: AccountId
    ) -> ProofOfInk.Choice?

    func proceduralPersonal(
        for familyIndex: ProofOfInkPallet.FamilyIndex,
        familyId: ProofOfInkPallet.FamilyId,
        personalId: ProofOfInkPallet.PersonalId
    ) -> ProofOfInk.Choice?
}

final class UserInkChoiceProvider: AnyProviderAutoCleaning {
    private enum Constants {
        static let entropy: Data? = try? EntropyGenerator().generateEntropy(of: 32).get()
    }
}

extension UserInkChoiceProvider: UserInkChoiceProviding {
    func procedural(
        for familyIndex: ProofOfInkPallet.FamilyIndex,
        variantIndex: ProofOfInkPallet.VariantIndex,
        familyId: ProofOfInkPallet.FamilyId,
        entropy: Data?
    ) -> ProofOfInk.Choice? {
        guard let concreteEntropy = entropy ?? Constants.entropy else {
            return nil
        }

        let proceduralSeed = entropyToSeed(entropy: [UInt8](concreteEntropy), variant: variantIndex)
        return ProofOfInk.Choice.procedural(.init(
            family: familyIndex,
            variantIndex: variantIndex,
            proceduralSeed: proceduralSeed,
            familyId: familyId
        ))
    }

    func proceduralAccount(
        for familyIndex: ProofOfInkPallet.FamilyIndex,
        familyId: ProofOfInkPallet.FamilyId,
        accountId: AccountId
    ) -> ProofOfInk.Choice? {
        ProofOfInk.Choice.proceduralAccount(.init(
            family: familyIndex,
            accountId: accountId,
            familyId: familyId
        ))
    }

    func proceduralPersonal(
        for familyIndex: ProofOfInkPallet.FamilyIndex,
        familyId: ProofOfInkPallet.FamilyId,
        personalId: ProofOfInkPallet.PersonalId
    ) -> ProofOfInk.Choice? {
        ProofOfInk.Choice.proceduralPersonal(.init(
            family: familyIndex,
            personalId: personalId,
            familyId: familyId
        ))
    }
}

private extension UserInkChoiceProvider {
    /// Adapted from:
    /// https://github.com/paritytech/individuality/blob/main/pallets/proof-of-ink/src/lib.rs#L1141
    func entropyToSeed(entropy: [UInt8], variant: ProofOfInkPallet.VariantIndex) -> ProofOfInkPallet.ProceduralSeed {
        var seed = [UInt8](repeating: 0, count: 4)
        let variantAsInt = Int(variant)
        var variantIndex = variantAsInt

        if variantIndex < 8 {
            seed = Array(entropy[variantIndex * 4 ..< variantIndex * 4 + 4])
        } else {
            var indices = [Int](repeating: 0, count: 4)
            for currentIndex in 0 ..< 4 {
                let range = 32 - currentIndex
                indices[currentIndex] = variantIndex % range
                for previousIndex in 0 ..< currentIndex where indices[currentIndex] >= indices[previousIndex] {
                    indices[currentIndex] += 1
                }
                seed[currentIndex] = entropy[indices[currentIndex]]
                variantIndex /= range
            }
        }
        return Data(seed)
    }
}
