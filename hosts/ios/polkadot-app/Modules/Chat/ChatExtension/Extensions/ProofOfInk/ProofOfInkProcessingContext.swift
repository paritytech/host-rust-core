import Foundation
import SubstrateSdk
import UIKit
import AsyncExtensions
import Individuality

actor ProofOfInkProcessingContext {
    private let context: ChatExtensionDiscoverContextProtocol
    private let sender: ChatExtensionBotProtocol
    private let logger: LoggerProtocol

    init(
        context: ChatExtensionDiscoverContextProtocol,
        sender: ChatExtensionBotProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.context = context
        self.sender = sender
        self.logger = logger
    }

    /// Process a stream of message events from the interactor
    func process(events: AnyAsyncSequence<DIM1MessageEvent>) async throws {
        for try await event in events {
            try await process(event: event)
        }
    }

    /// Process a single message event
    func process(event: DIM1MessageEvent) async throws {
        switch event {
        case let .tattooCommitted(candidate, familyId):
            try await handleTattooCommitted(
                for: candidate,
                familyId: familyId,
                sender: sender
            )
        case let .videoRecordConfirmed(candidate):
            try await handleVideoRecordConfirmed(
                sender: sender,
                selectedCandidate: candidate
            )
        case let .photoConfirmed(candidate):
            try await handlePhotoConfirmed(
                sender: sender,
                selectedCandidate: candidate
            )
        case let .evidenceStateUpdate(selectedCandidate, model):
            try await handleEvidenceUploadingState(
                model: model,
                selectedCandidate: selectedCandidate,
                sender: sender
            )
        case .evidenceApproved:
            await handleEvidenceApproved(sender: sender)
        case let .personhoodRegistered(personalId):
            try await handlePersonhoodRegistered(personalId: personalId)
        case let .fullUsernameClaimed(content):
            try await handleFullUsernameClaimed(content: content)
        }
    }
}

// MARK: - Event handling

extension ProofOfInkProcessingContext {
    func handleTattooCommitted(
        for selectedCandidate: ProofOfInkPallet.Candidate.Selected,
        familyId: ProofOfInkPallet.FamilyId,
        sender: ChatExtensionBotProtocol
    ) async throws {
        let prevMessages = try await context.getMessagesByContentKey(
            ProofOfInkMessageContentKey.tattooCommitted,
            with: sender
        )

        // Allow commitment only once for now
        guard prevMessages.isEmpty else {
            return
        }

        try await postTattooCommittedMessages(
            familyId: familyId,
            selectedCandidate: selectedCandidate,
            sender: sender
        )
    }

    func handleVideoRecordConfirmed(
        sender: ChatExtensionBotProtocol,
        selectedCandidate: ProofOfInkPallet.Candidate.Selected
    ) async throws {
        let prevMessages = try await context.getMessagesByContentKey(
            ProofOfInkMessageContentKey.videoEvidence,
            with: sender
        )

        guard prevMessages.isEmpty else {
            return
        }

        try await postVideoQueuedMessage(
            previewId: makePreviewId(for: selectedCandidate),
            sender: sender
        )
    }

    func handlePhotoConfirmed(
        sender: ChatExtensionBotProtocol,
        selectedCandidate: ProofOfInkPallet.Candidate.Selected
    ) async throws {
        let prevMessages = try await context.getMessagesByContentKey(
            ProofOfInkMessageContentKey.photoEvidence,
            with: sender
        )

        guard prevMessages.isEmpty else {
            return
        }

        let previewId = makePreviewId(for: selectedCandidate)

        try await postPhotoQueuedMessage(
            previewId: previewId,
            sender: sender
        )
    }

    func handleEvidenceUploadingState(
        model: ProofOfInkChatEvidenceModel,
        selectedCandidate: ProofOfInkPallet.Candidate.Selected,
        sender: ChatExtensionBotProtocol
    ) async throws {
        let previewId = makePreviewId(for: selectedCandidate)

        await updateEvidenceStateForPreviewIdOrLast(
            previewId,
            contentKey: ProofOfInkMessageContentKey.videoEvidence,
            status: model.videoItem.state,
            with: sender
        )

        await updateEvidenceStateForPreviewIdOrLast(
            previewId,
            contentKey: ProofOfInkMessageContentKey.photoEvidence,
            status: model.photoItem.state,
            with: sender
        )
    }

    func handleEvidenceApproved(
        sender: ChatExtensionBotProtocol
    ) async {
        // mark last video and photo evidences as reviewed
        await updateEvidenceStateForPreviewIdOrLast(
            nil,
            contentKey: ProofOfInkMessageContentKey.videoEvidence,
            status: .reviewed,
            with: sender
        )

        await updateEvidenceStateForPreviewIdOrLast(
            nil,
            contentKey: ProofOfInkMessageContentKey.photoEvidence,
            status: .reviewed,
            with: sender
        )
    }

    func handlePersonhoodRegistered(
        personalId: PeoplePallet.PersonalId
    ) async throws {
        let content = PersonhoodRegisteredMessageDecoder.Content(personalId: personalId)

        let existingMessages = try await context.getMessagesByContentKey(
            content.identifier,
            with: sender
        )

        guard existingMessages.isEmpty else {
            return
        }

        let messageContent: Chat.LocalMessage.Content = try .customRendered(
            .init(
                decoderId: MessageDecoderIdentifier.personhoodRegistered.rawValue,
                data: content.scaleEncoded(),
                identifier: content.identifier
            )
        )

        _ = try await context.sendNewMessage(
            from: sender,
            newContent: messageContent,
            messageDeliveryDelay: .immediate
        )
    }

    func handleFullUsernameClaimed(
        content: FullUsernameClaimedMessageDecoder.Content
    ) async throws {
        let existingMessages = try await context.getMessagesByContentKey(
            content.identifier,
            with: sender
        )

        guard existingMessages.isEmpty else {
            return
        }

        let messageContent: Chat.LocalMessage.Content = try .customRendered(
            .init(
                decoderId: MessageDecoderIdentifier.fullUsernameClaimed.rawValue,
                data: content.scaleEncoded(),
                identifier: content.identifier
            )
        )

        _ = try await context.sendNewMessage(
            from: sender,
            newContent: messageContent,
            messageDeliveryDelay: .immediate
        )
    }
}

// MARK: - Identifier crafting

private extension ProofOfInkProcessingContext {
    func makePreviewId(for selectedCandidate: ProofOfInkPallet.Candidate.Selected) -> String {
        String(selectedCandidate.since)
    }
}

// MARK: - Messaging

private extension ProofOfInkProcessingContext {
    func postTattooCommittedMessages(
        familyId: ProofOfInkPallet.FamilyId,
        selectedCandidate: ProofOfInkPallet.Candidate.Selected,
        sender: ChatExtensionBotProtocol
    ) async throws {
        let payload = TattooCommitmentMessageDecoder.Payload(
            familyId: familyId,
            design: selectedCandidate.design,
            since: selectedCandidate.since
        )

        let content = try Chat.LocalMessage.Content.customRendered(
            .init(
                decoderId: MessageDecoderIdentifier.tattooCommitted.rawValue,
                data: payload.scaleEncoded(),
                identifier: ProofOfInkMessageContentKey.tattooCommitted
            )
        )

        try await context.sendNewMessage(
            to: sender,
            newContent: content,
            messageDeliveryDelay: .immediate
        )

        let detailsString1 = String(localized: .Tattoo.messageCommitDetail1)
        let detailsString2 = String(localized: .Tattoo.messageCommitDetail2)

        try await context.sendNewMessage(
            from: sender,
            newContent: .text(detailsString1),
            messageDeliveryDelay: .immediate
        )

        try await context.sendNewMessage(
            from: sender,
            newContent: .text(detailsString2),
            messageDeliveryDelay: .immediate
        )

        if let stencilFile = try await stencilFile(
            with: selectedCandidate.design,
            familyId: familyId
        ) {
            try await context.sendNewMessage(
                from: sender,
                newContent: .file(stencilFile),
                messageDeliveryDelay: .immediate
            )
        }

        if let manualFile = try await manualFile() {
            try await context.sendNewMessage(
                from: sender,
                newContent: .file(manualFile),
                messageDeliveryDelay: .immediate
            )
        }

        // Provide Photo and Video Documentation
        let details3 = String(localized: .Tattoo.messageCommitEvidenceInstructions)
        try await context.sendNewMessage(
            from: sender,
            newContent: .text(details3),
            messageDeliveryDelay: .immediate
        )

        let videoEvidenceMessage = String(localized: .Tattoo.messageCommitEvidenceVideo)
        try await context.sendNewMessage(
            from: sender,
            newContent: .text(videoEvidenceMessage),
            messageDeliveryDelay: .immediate
        )
    }

    func stencilFile(
        with design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId
    ) async throws -> Chat.LocalMessage.Content.File? {
        guard let file = Chat.LocalMessage.Content.File(
            type: .pdf,
            location: .relativeDocumentsPath("tattoo-stencil"),
            customName: "Stencil.PDF",
            text: .init(localized: .Tattoo.pdfTextStencil)
        ) else {
            return nil
        }

        do {
            let generator = StencilPDFGenerator(imageProvider: TattooImageProvider(
                design: design,
                familyId: familyId
            ))
            _ = try await generator
                .generateStencilPDF(outputFileURL: file.url)
                .asyncExecute()
            return file
        } catch {
            logger.error("Error during PDF generation: \(error.localizedDescription)")
            return nil
        }
    }

    func manualFile() async throws -> Chat.LocalMessage.Content.File? {
        .init(
            type: .pdf,
            location: .bundleName("tattoo-manual"),
            customName: "Manual.PDF",
            text: .init(localized: .Tattoo.pdfTextManual)
        )
    }

    func postVideoQueuedMessage(
        previewId: String,
        sender: ChatExtensionBotProtocol
    ) async throws {
        let payload = EvidenceMessageDecoder.Payload(
            previewId: previewId,
            status: .waitingToUpload,
            timestamp: Date().toChatTimestamp()
        )

        let content = try Chat.LocalMessage.Content.customRendered(
            .init(
                decoderId: MessageDecoderIdentifier.evidenceVideo.rawValue,
                data: payload.scaleEncoded(),
                identifier: ProofOfInkMessageContentKey.videoEvidence
            )
        )

        _ = try await context.sendNewMessage(
            to: sender,
            newContent: content,
            messageDeliveryDelay: .immediate
        )

        let videoEvidenceMessage = String(localized: .Tattoo.messageEvidencePhotoNext)
        _ = try await context.sendNewMessage(
            from: sender,
            newContent: .text(videoEvidenceMessage),
            messageDeliveryDelay: .immediate
        )
    }

    func postPhotoQueuedMessage(
        previewId: String,
        sender: ChatExtensionBotProtocol
    ) async throws {
        let payload = EvidenceMessageDecoder.Payload(
            previewId: previewId,
            status: .uploading(progress: 0),
            timestamp: Date().toChatTimestamp()
        )

        let content = try Chat.LocalMessage.Content.customRendered(
            .init(
                decoderId: MessageDecoderIdentifier.evidencePhoto.rawValue,
                data: payload.scaleEncoded(),
                identifier: ProofOfInkMessageContentKey.photoEvidence
            )
        )

        _ = try await context.sendNewMessage(
            to: sender,
            newContent: content,
            messageDeliveryDelay: .immediate
        )
    }

    func updateEvidenceStateForPreviewIdOrLast(
        _ previewId: String?,
        contentKey: String,
        status: ProofOfInkChatEvidenceItemModel.State,
        with sender: ChatExtensionBotProtocol
    ) async {
        do {
            logger.debug("Updating evidence status: \(contentKey) \(status)")

            let evidenceMessages = try await context.getMessagesByContentKey(
                contentKey,
                with: sender
            )

            let optMessage: Chat.LocalMessage? =
                if let previewId {
                    evidenceMessages.first { message in
                        guard case let .customRendered(renderData) = message.content else {
                            return false
                        }

                        do {
                            let decoder = try ScaleDecoder(data: renderData.data)
                            let payload = try EvidenceMessageDecoder.Payload(scaleDecoder: decoder)

                            return payload.previewId == previewId
                        } catch {
                            logger.error("Can't decode evidence message: \(error)")
                            return false
                        }
                    }
                } else {
                    evidenceMessages.last
                }

            guard let message = optMessage else {
                logger.debug("No evidence found")
                return
            }

            guard case let .customRendered(renderData) = message.content else {
                logger.error("Evidence must be custom rendered message")
                return
            }

            let decoder = try ScaleDecoder(data: renderData.data)
            let payload = try EvidenceMessageDecoder.Payload(scaleDecoder: decoder)

            guard payload.status != status else {
                logger.debug("Status didn't change")
                return
            }

            let newPayload = EvidenceMessageDecoder.Payload(
                previewId: payload.previewId,
                status: status,
                timestamp: Date().toChatTimestamp()
            )

            let newContent = try Chat.LocalMessage.Content.customRendered(
                .init(
                    decoderId: renderData.decoderId,
                    data: newPayload.scaleEncoded(),
                    identifier: contentKey
                )
            )

            try await context.modifyMessageContent(
                messageId: message.messageId,
                content: newContent
            )

            logger.debug("Evidence status updated: \(contentKey)")
        } catch {
            logger.error("Can't mark video as approved: \(error)")
        }
    }
}
