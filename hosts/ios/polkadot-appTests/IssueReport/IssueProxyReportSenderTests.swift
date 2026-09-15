import Foundation
import Testing
@testable import polkadot_app

struct IssueProxyReportSenderTests {
    private let endpoint = "https://reports.example/v1/issues"
    private let report = IssueReport(
        description: "The screen froze 🐛",
        logs: Data([0x50, 0x4B, 0x03, 0x04]),
        screenshot: Data([0x89, 0x50, 0x4E, 0x47])
    )

    @Test func postsAuthenticatedProxyMultipart() async throws {
        let url = try #require(URL(string: endpoint))
        let client = StubHTTPLoader()
        client.setStub(.init(statusCode: 201), for: url)
        let configuration = try IssueProxyConfiguration(endpoint: endpoint, apiKey: "app-key")
        let sender = IssueProxyReportSender(configuration: { configuration }, client: client)

        try await sender.send(report)

        let request = try #require(client.recordedRequests.first)
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
        var body = Data((
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\niOS app issue\r\n" +
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"body\"\r\n\r\nThe screen froze 🐛\r\n" +
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"screenshot\"; " +
                "filename=\"screenshot.png\"\r\nContent-Type: image/png\r\n\r\n"
        ).utf8)
        body.append(report.screenshot)
        body.append(Data((
            "\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"logs\"; " +
                "filename=\"logs.zip\"\r\nContent-Type: application/zip\r\n\r\n"
        ).utf8))
        body.append(report.logs)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var expected = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        expected.httpMethod = "POST"
        expected.setValue("Bearer app-key", forHTTPHeaderField: "Authorization")
        expected.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        expected.httpBody = body
        #expect(client.recordedRequests == [expected])
        #expect(request.httpBody == body)
    }

    @Test func missingOrUnsafeConfigurationMakesNoRequest() async {
        let client = StubHTTPLoader()
        let invalidValues = [
            ("", "app-key"),
            (endpoint, ""),
            ("http://reports.example/v1/issues", "app-key"),
            ("https://user:password@reports.example/v1/issues", "app-key"),
            ("https://reports.example/v1/issues#fragment", "app-key"),
            (endpoint, "app-key\r\nX-Other: value")
        ]
        for (endpoint, apiKey) in invalidValues {
            let sender = IssueProxyReportSender(
                configuration: { try IssueProxyConfiguration(endpoint: endpoint, apiKey: apiKey) },
                client: client
            )
            await #expect(throws: IssueReportSubmissionError.unavailable) {
                try await sender.send(report)
            }
        }
        #expect(client.recordedRequests.isEmpty)
    }

    @Test(arguments: [200, 202, 302, 401, 413, 500])
    func onlyCreatedIsSuccessful(status: Int) async throws {
        let url = try #require(URL(string: endpoint))
        let client = StubHTTPLoader()
        client.setStub(.init(statusCode: status), for: url)
        let configuration = try IssueProxyConfiguration(endpoint: endpoint, apiKey: "app-key")
        let sender = IssueProxyReportSender(configuration: { configuration }, client: client)

        await #expect(throws: IssueReportSubmissionError.rejected) {
            try await sender.send(report)
        }
        #expect(client.recordedRequests.count == 1)
    }

    @Test func enforcesScreenshotAndWholeMultipartLimitsBeforeSending() async throws {
        let client = StubHTTPLoader()
        let configuration = try IssueProxyConfiguration(endpoint: endpoint, apiKey: "app-key")
        let sender = IssueProxyReportSender(configuration: { configuration }, client: client)
        let reports = [
            IssueReport(description: "Issue", logs: report.logs, screenshot: Data(count: 10 * 1_024 * 1_024 + 1)),
            IssueReport(
                description: "Issue",
                logs: Data(count: 25 * 1_024 * 1_024 - report.screenshot.count),
                screenshot: report.screenshot
            )
        ]

        for report in reports {
            await #expect(throws: IssueReportSubmissionError.tooLarge) {
                try await sender.send(report)
            }
        }
        #expect(client.recordedRequests.isEmpty)
    }

    @Test func refusesRedirectBeforeAnotherHostReceivesTheReport() async throws {
        let url = try #require(URL(string: endpoint))
        let request = URLRequest(url: url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 307,
            httpVersion: nil,
            headerFields: ["Location": "https://another.example/v1/issues"]
        ))
        let redirected = await withCheckedContinuation { continuation in
            IssueReportRedirectDelegate().urlSession(
                .shared,
                task: URLSession.shared.dataTask(with: request),
                willPerformHTTPRedirection: response,
                newRequest: request
            ) { continuation.resume(returning: $0) }
        }
        #expect(redirected == nil)
    }

    @Test func acceptsReportsExactlyAtTheSizeLimits() async throws {
        let url = try #require(URL(string: endpoint))
        let client = StubHTTPLoader()
        client.setStub(.init(statusCode: 201), for: url)
        let configuration = try IssueProxyConfiguration(endpoint: endpoint, apiKey: "app-key")
        let sender = IssueProxyReportSender(configuration: { configuration }, client: client)
        let screenshot = Data(count: 10 * 1_024 * 1_024)
        try await sender.send(IssueReport(description: "Issue", logs: report.logs, screenshot: screenshot))
        let initialBody = try #require(client.recordedRequests.first?.httpBody)
        let logs = Data(count: 25 * 1_024 * 1_024 - initialBody.count + report.logs.count)

        try await sender.send(IssueReport(description: "Issue", logs: logs, screenshot: screenshot))

        #expect(client.recordedRequests.last?.httpBody?.count == 25 * 1_024 * 1_024)
    }
}
