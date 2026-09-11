import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateSdkExt
import ChainRegistry

protocol SearchUsernameOperationFactory {
    func searchUsername(for request: UsernameRequestModel) async throws -> [UsernameResponseModel]
    func allUsernames() async throws -> [UsernameResponseModel]
}

final class SearchUsernameFactory: SearchUsernameOperationFactory {
    private let chatContactRepositoryFactory: ChatContactRepositoryMaking
    private let chainModel: ChainModel

    init(
        chatContactRepositoryFactory: ChatContactRepositoryMaking,
        chainModel: ChainModel
    ) {
        self.chatContactRepositoryFactory = chatContactRepositoryFactory
        self.chainModel = chainModel
    }

    func searchUsername(for request: UsernameRequestModel) async throws -> [UsernameResponseModel] {
        let contactsPredicate: NSPredicate = .contact(beginsWith: request.prefix)
        let contacts = try await chatContactRepositoryFactory
            .createRepository(forFilter: contactsPredicate)
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
        let chainFormat = chainModel.chainFormat
        return contacts
            .compactMap {
                try? UsernameResponseModel(contact: $0, chainFormat: chainFormat)
            }
    }

    func allUsernames() async throws -> [UsernameResponseModel] {
        let contactsPredicate: NSPredicate = .isContact()
        let contacts = try await chatContactRepositoryFactory
            .createRepository(forFilter: contactsPredicate)
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()
        let chainFormat = chainModel.chainFormat
        return contacts
            .compactMap {
                try? UsernameResponseModel(contact: $0, chainFormat: chainFormat)
            }
    }
}

private extension UsernameResponseModel {
    init(contact: Chat.Contact, chainFormat: ChainFormat) throws {
        accountId = try contact.accountId.toAddress(using: chainFormat)
        username = Username(value: contact.username)
        createdAt = ""
        updatedAt = ""
        status = .assigned
    }
}

private extension NSPredicate {
    static func contact(beginsWith prefix: String) -> NSPredicate {
        let begins = NSPredicate(
            format: "%K BEGINSWITH[c] %@",
            #keyPath(CDChatContact.username),
            prefix
        )

        return NSCompoundPredicate(andPredicateWithSubpredicates: [begins, isContact()])
    }

    static func isContact() -> NSPredicate {
        NSPredicate(
            format: "%K == nil AND %K == nil",
            #keyPath(CDChatContact.chatRequest),
            #keyPath(CDChatContact.game)
        )
    }
}
