import Foundation

struct IssueReport: Sendable {
    let description: String
    let logs: Data
    let screenshot: Data
}

protocol IssueReportSending: Sendable {
    func send(_ report: IssueReport) async throws
}

struct MockIssueReportSender: IssueReportSending {
    func send(_: IssueReport) async throws {
        try await Task.sleep(for: .seconds(1))
    }
}
