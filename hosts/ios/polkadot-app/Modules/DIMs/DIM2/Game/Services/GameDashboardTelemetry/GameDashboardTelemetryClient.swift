import Foundation
import Operation_iOS
import SubstrateSdk

/// Stateless transport for the DIM2 debug dashboard.
///
/// Each call performs one POST and throws a typed [GameDashboardTelemetryError]
/// on failure. Retry, scheduling, and lifecycle live in the emitter, not here.
protocol GameDashboardTelemetryClienting {
    func postRegistration(_ payload: GameDashboardPayloads.Registration) async throws
    func postReporting(_ payload: GameDashboardPayloads.Reporting) async throws
    func postEnd(_ payload: GameDashboardPayloads.End) async throws
}

final class GameDashboardTelemetryClient: GameDashboardTelemetryClienting {
    private let baseURL: URL
    private let urlSession: any HTTPDataLoading
    private let logger: LoggerProtocol

    init(
        baseURL: URL,
        urlSession: any HTTPDataLoading = URLSession.shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.logger = logger
    }

    func postRegistration(_ payload: GameDashboardPayloads.Registration) async throws {
        try await post(payload: payload, path: "/api/donate/registration")
    }

    func postReporting(_ payload: GameDashboardPayloads.Reporting) async throws {
        try await post(payload: payload, path: "/api/donate/reporting")
    }

    func postEnd(_ payload: GameDashboardPayloads.End) async throws {
        try await post(payload: payload, path: "/api/donate/end")
    }
}

private extension GameDashboardTelemetryClient {
    func post(payload: some Encodable, path: String) async throws {
        let url = baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = HttpMethod.post.rawValue
        request.setValue(
            HttpContentType.json.rawValue,
            forHTTPHeaderField: HttpHeaderKey.contentType.rawValue
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw GameDashboardTelemetryError.encodingFailed(underlying: error)
        }

        let response: URLResponse
        do {
            (_, response) = try await urlSession.data(for: request)
        } catch {
            throw GameDashboardTelemetryError.transient(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GameDashboardTelemetryError.transient(
                underlying: URLError(.badServerResponse)
            )
        }

        switch http.statusCode {
        case 200 ... 299:
            return
        case 429,
             500 ... 599:
            throw GameDashboardTelemetryError.transient(
                underlying: URLError(.init(rawValue: http.statusCode))
            )
        default:
            throw GameDashboardTelemetryError.nonRetryable(
                statusCode: http.statusCode,
                underlying: nil
            )
        }
    }
}
