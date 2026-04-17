import AppKit
import CryptoKit
import Foundation
import Network

struct GoogleCalendarSession: Equatable {
    let account: GoogleCalendarAccount
    let accessToken: String
}

enum GoogleCalendarSignInError: LocalizedError {
    case notConfigured
    case missingPresentingWindow
    case noPreviousSignIn
    case invalidAuthorizationResponse
    case invalidTokenResponse
    case stateMismatch
    case authorizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            L10n.googleCalendarClientIDMissingMessage
        case .missingPresentingWindow:
            L10n.googleCalendarMissingPresentingWindow
        case .noPreviousSignIn:
            L10n.googleCalendarNoPreviousSession
        case .invalidAuthorizationResponse, .invalidTokenResponse:
            L10n.googleCalendarUnexpectedResponse
        case .stateMismatch:
            L10n.googleCalendarUnexpectedResponse
        case let .authorizationFailed(message):
            message
        }
    }
}

@MainActor
protocol GoogleCalendarSignInProviding: AnyObject {
    var isConfigured: Bool { get }
    var hasPreviousSignIn: Bool { get }

    func restorePreviousSignIn() async throws -> GoogleCalendarSession
    func signIn(withPresentingWindow window: NSWindow) async throws -> GoogleCalendarSession
    func refreshCurrentSession() async throws -> GoogleCalendarSession?
    func disconnect() async throws
}

@MainActor
final class GoogleCalendarSignInAdapter: NSObject, GoogleCalendarSignInProviding {
    private static let keychainKey = "googleCalendarOAuthSession"
    private static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    private static let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
    private static let scopes = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/calendar.readonly",
    ]
    private static let tokenRefreshLeeway: TimeInterval = 60

    private let urlSession: URLSession

    var isConfigured: Bool {
        GoogleCalendarConfiguration.isConfigured
    }

    var hasPreviousSignIn: Bool {
        storedSession != nil
    }

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        super.init()
    }

    func restorePreviousSignIn() async throws -> GoogleCalendarSession {
        guard let storedSession else {
            throw GoogleCalendarSignInError.noPreviousSignIn
        }

        let refreshed = try await refreshedSession(from: storedSession)
        save(refreshed)
        return refreshed.session
    }

    func signIn(withPresentingWindow window: NSWindow) async throws -> GoogleCalendarSession {
        guard let clientID = GoogleCalendarConfiguration.clientID else {
            throw GoogleCalendarSignInError.notConfigured
        }

        let clientSecret = GoogleCalendarConfiguration.clientSecret
        let pkce = PKCE.generate()
        let state = PKCE.randomURLSafeString(length: 32)
        let redirectServer = try await LoopbackRedirectServer()
        let redirect = redirectServer.redirectURL
        let authorizationURL = Self.makeAuthorizationURL(
            clientID: clientID,
            redirectURL: redirect,
            codeChallenge: pkce.codeChallenge,
            state: state
        )

        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        guard NSWorkspace.shared.open(authorizationURL) else {
            throw GoogleCalendarSignInError.invalidAuthorizationResponse
        }

        let callbackURL = try await redirectServer.waitForCallback()
        NSApp.activate(ignoringOtherApps: true)

        let code = try Self.extractAuthorizationCode(from: callbackURL, expectedState: state)
        let tokenResponse = try await exchangeAuthorizationCode(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURL: redirect,
            code: code,
            codeVerifier: pkce.codeVerifier
        )
        let account = try await fetchAccount(accessToken: tokenResponse.accessToken)
        let session = StoredSession(
            account: account,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expirationDate: tokenResponse.expirationDate
        )
        save(session)
        return session.session
    }

    func refreshCurrentSession() async throws -> GoogleCalendarSession? {
        guard let storedSession else {
            return nil
        }

        let refreshed = try await refreshedSession(from: storedSession)
        save(refreshed)
        return refreshed.session
    }

    func disconnect() async throws {
        if let storedSession {
            try await revokeIfPossible(token: storedSession.refreshToken ?? storedSession.accessToken)
        }
        KeychainService.delete(key: Self.keychainKey)
    }

    private var storedSession: StoredSession? {
        guard let json = KeychainService.load(key: Self.keychainKey, accessPolicy: .standard),
              let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    private func save(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8)
        else { return }

        try? KeychainService.save(key: Self.keychainKey, value: json, accessPolicy: .standard)
    }

    private func refreshedSession(from storedSession: StoredSession) async throws -> StoredSession {
        guard storedSession.expirationDate.timeIntervalSinceNow <= Self.tokenRefreshLeeway else {
            return storedSession
        }

        guard let clientID = GoogleCalendarConfiguration.clientID,
              let refreshToken = storedSession.refreshToken
        else {
            return storedSession
        }

        let tokenResponse = try await refreshAccessToken(
            clientID: clientID,
            clientSecret: GoogleCalendarConfiguration.clientSecret,
            refreshToken: refreshToken
        )
        return StoredSession(
            account: storedSession.account,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            expirationDate: tokenResponse.expirationDate
        )
    }

    private func exchangeAuthorizationCode(
        clientID: String,
        clientSecret: String?,
        redirectURL: URL,
        code: String,
        codeVerifier: String
    ) async throws -> TokenResponse {
        let body = Self.makeTokenRequestBody(
            clientID: clientID,
            clientSecret: clientSecret,
            parameters: [
                "code": code,
                "code_verifier": codeVerifier,
                "grant_type": "authorization_code",
                "redirect_uri": redirectURL.absoluteString,
            ]
        )
        return try await tokenRequest(body: body)
    }

    private func refreshAccessToken(clientID: String, clientSecret: String?, refreshToken: String) async throws -> TokenResponse {
        let body = Self.makeTokenRequestBody(
            clientID: clientID,
            clientSecret: clientSecret,
            parameters: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ]
        )
        return try await tokenRequest(body: body)
    }

    static func makeTokenRequestBody(
        clientID: String,
        clientSecret: String?,
        parameters: [String: String]
    ) -> [String: String] {
        var body = parameters
        body["client_id"] = clientID
        if let clientSecret, !clientSecret.isEmpty {
            body["client_secret"] = clientSecret
        }
        return body
    }

    private func tokenRequest(body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(body).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleCalendarSignInError.invalidTokenResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let detail = Self.responseDetail(from: data) ?? L10n.googleCalendarUnexpectedResponse
            throw GoogleCalendarSignInError.authorizationFailed(
                L10n.googleCalendarHTTPError(httpResponse.statusCode, detail)
            )
        }

        let payload = try JSONDecoder().decode(TokenPayload.self, from: data)
        guard let expirationDate = Calendar.current.date(byAdding: .second, value: payload.expiresIn, to: Date()) else {
            throw GoogleCalendarSignInError.invalidTokenResponse
        }

        return TokenResponse(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expirationDate: expirationDate
        )
    }

    private func fetchAccount(accessToken: String) async throws -> GoogleCalendarAccount {
        var request = URLRequest(url: Self.userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleCalendarSignInError.invalidAuthorizationResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let detail = Self.responseDetail(from: data) ?? L10n.googleCalendarUnexpectedResponse
            throw GoogleCalendarSignInError.authorizationFailed(
                L10n.googleCalendarHTTPError(httpResponse.statusCode, detail)
            )
        }

        let payload = try JSONDecoder().decode(UserInfoPayload.self, from: data)
        return GoogleCalendarAccount(
            id: payload.subject,
            displayName: payload.name ?? payload.email ?? L10n.googleCalendarUnknownAccount,
            email: payload.email ?? ""
        )
    }

    private func revokeIfPossible(token: String) async throws {
        var request = URLRequest(url: Self.revokeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(["token": token]).data(using: .utf8)
        _ = try await urlSession.data(for: request)
    }

    private static func makeAuthorizationURL(
        clientID: String,
        redirectURL: URL,
        codeChallenge: String,
        state: String
    ) -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURL.absoluteString),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "access_type", value: "offline"),
            .init(name: "include_granted_scopes", value: "true"),
            .init(name: "prompt", value: "consent"),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return components.url!
    }

    private static func extractAuthorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw GoogleCalendarSignInError.invalidAuthorizationResponse
        }

        let queryItems = Dictionary(
            uniqueKeysWithValues: components.queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? []
        )
        if let error = queryItems["error"] {
            let description = queryItems["error_description"] ?? error
            throw GoogleCalendarSignInError.authorizationFailed(description)
        }

        guard queryItems["state"] == expectedState else {
            throw GoogleCalendarSignInError.stateMismatch
        }

        guard let code = queryItems["code"], !code.isEmpty else {
            throw GoogleCalendarSignInError.invalidAuthorizationResponse
        }

        return code
    }

    private static func formEncoded(_ parameters: [String: String]) -> String {
        parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
    }

    private static func responseDetail(from data: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        if let errorDescription = payload["error_description"] as? String {
            return errorDescription
        }
        if let error = payload["error"] as? String {
            return error
        }
        return String(data: data, encoding: .utf8)
    }

}

private struct StoredSession: Codable {
    let account: GoogleCalendarAccount
    let accessToken: String
    let refreshToken: String?
    let expirationDate: Date

    var session: GoogleCalendarSession {
        GoogleCalendarSession(account: account, accessToken: accessToken)
    }
}

private struct TokenPayload: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct TokenResponse {
    let accessToken: String
    let refreshToken: String?
    let expirationDate: Date
}

private struct UserInfoPayload: Decodable {
    let subject: String
    let name: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case name
        case email
    }
}

private struct PKCE {
    let codeVerifier: String
    let codeChallenge: String

    static func generate() -> PKCE {
        let verifier = randomURLSafeString(length: 64)
        let challenge = Data(CryptoKit.SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        return PKCE(codeVerifier: verifier, codeChallenge: challenge)
    }

    fileprivate static func randomURLSafeString(length: Int) -> String {
        let bytes = (0 ..< length).map { _ in UInt8.random(in: 0 ... 255) }
        return Data(bytes).base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}

private final class LoopbackRedirectServer: @unchecked Sendable {
    private(set) var redirectURL: URL

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.dahlia.google-oauth-loopback")
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var readinessContinuation: CheckedContinuation<Void, Error>?

    init() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        redirectURL = URL(string: "http://127.0.0.1")!

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readinessContinuation = continuation

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.readinessContinuation?.resume()
                    self?.readinessContinuation = nil
                case let .failed(error):
                    self?.readinessContinuation?.resume(throwing: error)
                    self?.readinessContinuation = nil
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }

            listener.start(queue: queue)
        }

        guard let port = listener.port?.rawValue else {
            throw GoogleCalendarSignInError.invalidAuthorizationResponse
        }

        self.redirectURL = URL(string: "http://127.0.0.1:\(port)/oauth2redirect")!
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            callbackContinuation = continuation
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.callbackContinuation?.resume(throwing: error)
                self.callbackContinuation = nil
                self.shutdown()
                return
            }

            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let url = self.parseRequestURL(from: request)
            else {
                self.reply(to: connection, status: "400 Bad Request", body: "Invalid OAuth redirect.")
                self.callbackContinuation?.resume(throwing: GoogleCalendarSignInError.invalidAuthorizationResponse)
                self.callbackContinuation = nil
                self.shutdown()
                return
            }

            self.reply(to: connection, status: "200 OK", body: "Google authentication completed. You can close this window and return to Dahlia.")
            self.callbackContinuation?.resume(returning: url)
            self.callbackContinuation = nil
            self.shutdown()
        }
    }

    private func parseRequestURL(from request: String) -> URL? {
        guard let firstLine = request.split(separator: "\r\n").first else {
            return nil
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var components = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)
        let pathAndQuery = String(parts[1])
        if let separatorIndex = pathAndQuery.firstIndex(of: "?") {
            components?.path = String(pathAndQuery[..<separatorIndex])
            components?.percentEncodedQuery = String(pathAndQuery[pathAndQuery.index(after: separatorIndex)...])
        } else {
            components?.path = pathAndQuery
        }
        return components?.url
    }

    private func reply(to connection: NWConnection, status: String, body: String) {
        let html = """
        <html>
        <head><meta charset="utf-8"></head>
        <body style="font-family:-apple-system, sans-serif;padding:24px;">
        <p>\(body)</p>
        </body>
        </html>
        """
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func shutdown() {
        listener.cancel()
    }
}
