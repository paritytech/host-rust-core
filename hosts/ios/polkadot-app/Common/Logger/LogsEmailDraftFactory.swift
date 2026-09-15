import Foundation
import ZipArchive

protocol LogsEmailDraftMaking {
    func makeLogsDraft() -> EmailDraft?
}

final class LogsEmailDraftFactory: LogsEmailDraftMaking {
    private lazy var subjectDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        return dateFormatter
    }()

    func makeLogsDraft() -> EmailDraft? {
        guard
            let logsURL = fileManager.logsDirectoryURL(),
            let docsURL = documentDirectoryURL()
        else {
            return nil
        }

        let zipName = "Logs.zip"
        let zipURL = docsURL.appendingPathComponent(zipName)

        if fileManager.fileExists(atPath: zipURL.path) {
            try? fileManager.removeItem(at: zipURL)
        }

        let success = SSZipArchive.createZipFile(
            atPath: zipURL.path,
            withContentsOfDirectory: logsURL.path
        )

        guard success, let data = try? Data(contentsOf: zipURL) else {
            return nil
        }

        return EmailDraft(
            subject: "\(subjectDateFormatter.string(from: Date())) - iOS",
            message: "\n\n\n",
            recipients: ["game@novasama.io"],
            attachment: .init(
                data: data,
                mimeType: "application/octet-stream",
                name: zipName,
                url: zipURL
            )
        )
    }
}

private extension LogsEmailDraftFactory {
    var fileManager: FileManager {
        .default
    }

    func documentDirectoryURL() -> URL? {
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        return urls.last ?? nil
    }
}
