import Testing
import Foundation
@testable import AgendumNeo

/// A `URLProtocol` stub that returns a single canned HTTP response for any
/// request. The canned response is held in a lock-guarded static so it can be
/// set per-test; the suite is `.serialized` so two tests never race on it.
private final class StubURLProtocol: URLProtocol {
    struct Stub: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    /// A `Sendable`, lock-guarded box holding the current canned response.
    /// URLProtocol instances are created by the loading system, so the response
    /// can't be injected per-instance; it lives here. Stored in an immutable
    /// `static let` so Swift 6 strict concurrency is satisfied without
    /// `nonisolated(unsafe)` — all mutation goes through the lock.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stub: Stub?
        private var capturedBody: Data?

        func set(_ value: Stub?) {
            lock.lock(); defer { lock.unlock() }
            stub = value
        }

        func get() -> Stub? {
            lock.lock(); defer { lock.unlock() }
            return stub
        }

        func setBody(_ value: Data?) {
            lock.lock(); defer { lock.unlock() }
            capturedBody = value
        }

        func body() -> Data? {
            lock.lock(); defer { lock.unlock() }
            return capturedBody
        }
    }

    private static let box = Box()

    static func setStub(_ stub: Stub) { box.set(stub) }
    static func reset() { box.set(nil); box.setBody(nil) }
    private static func currentStub() -> Stub? { box.get() }

    /// The decoded request body of the most recent stubbed request, so tests can
    /// assert what variables/query the client actually sent.
    static func capturedRequestBody() -> Data? { box.body() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.box.setBody(Self.readBody(from: request))
        guard let stub = Self.currentStub(), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Read a request body from either `httpBody` or, as URLSession usually
    /// hands it to a protocol, `httpBodyStream`.
    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// A `URLSession` configured to route all traffic through this stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private let testNamespace = Namespace(
    host: "github.com",
    accountLogin: "octocat",
    owner: "acme",
    kind: .org
)

@Suite("GitHubClient.fetchInbox SSO handling", .serialized)
struct GitHubClientTests {

    private func makeClient() -> GitHubClient {
        GitHubClient(host: "github.com", token: "test-token", session: StubURLProtocol.makeSession())
    }

    @Test("SAML errors array with X-GitHub-SSO does not throw and yields a restriction + empty snapshot")
    func samlErrorsArray() async throws {
        defer { StubURLProtocol.reset() }
        let body = """
        {
          "data": null,
          "errors": [
            {
              "type": "FORBIDDEN",
              "message": "Resource protected by organization SAML enforcement. You must grant your OAuth token access to this organization.",
              "extensions": { "saml_failure": true }
            }
          ]
        }
        """
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: [
                "Content-Type": "application/json",
                "X-GitHub-SSO": "required; url=https://github.com/orgs/acme/sso?authorization_request=ABC"
            ],
            body: Data(body.utf8)
        ))

        let client = makeClient()
        let result = try await client.fetchInbox(for: testNamespace)

        #expect(result.restriction != nil)
        #expect(result.restriction?.authorizationURL?.absoluteString
                == "https://github.com/orgs/acme/sso?authorization_request=ABC")
        #expect(result.snapshot.authoredPRs.isEmpty)
        #expect(result.snapshot.reviewRequestedPRs.isEmpty)
        #expect(result.snapshot.assignedIssues.isEmpty)
    }

    @Test("SAML errors array alongside partial data keeps the visible rows and sets a restriction")
    func samlErrorsWithPartialData() async throws {
        defer { StubURLProtocol.reset() }
        // Shape (a) per GitHub: HTTP 200 with the accessible results in `data`
        // AND a SAML FORBIDDEN error for the parts the token can't see.
        let body = """
        {
          "data": {
            "authored": {
              "nodes": [
                {
                  "__typename": "PullRequest",
                  "id": "PR_1",
                  "number": 7,
                  "title": "Visible PR",
                  "url": "https://github.com/acme/repo/pull/7",
                  "updatedAt": "2026-01-01T00:00:00Z",
                  "repository": { "nameWithOwner": "acme/repo" }
                }
              ]
            },
            "reviewRequested": { "nodes": [] },
            "assignedIssues": { "nodes": [] }
          },
          "errors": [
            {
              "type": "FORBIDDEN",
              "message": "Resource protected by organization SAML enforcement.",
              "extensions": { "saml_failure": true }
            }
          ]
        }
        """
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        ))

        let client = makeClient()
        let result = try await client.fetchInbox(for: testNamespace)

        #expect(result.restriction != nil)
        #expect(result.snapshot.authoredPRs.count == 1)
        #expect(result.snapshot.authoredPRs.first?.title == "Visible PR")
    }

    @Test("Empty data with partial-results header yields ssoPartialResults")
    func partialResultsHeader() async throws {
        defer { StubURLProtocol.reset() }
        let body = """
        {
          "data": {
            "authored": { "nodes": [] },
            "reviewRequested": { "nodes": [] },
            "assignedIssues": { "nodes": [] }
          }
        }
        """
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: [
                "Content-Type": "application/json",
                "X-GitHub-SSO": "partial-results; organizations=1"
            ],
            body: Data(body.utf8)
        ))

        let client = makeClient()
        let result = try await client.fetchInbox(for: testNamespace)

        #expect(result.restriction == .ssoPartialResults)
        #expect(result.snapshot.authoredPRs.isEmpty)
    }

    @Test("Fully-locked org: empty searches plus a SAML probe error yields a restriction, not a blank inbox")
    func orgProbeSAMLError() async throws {
        defer { StubURLProtocol.reset() }
        // What the org-access probe produces when search sees nothing but the
        // org is SSO-locked: searches return empty, `organization(login:)` is
        // nulled with a FORBIDDEN / saml_failure error at its path.
        let body = """
        {
          "data": {
            "orgAccessProbe": null,
            "authored": { "nodes": [] },
            "reviewRequested": { "nodes": [] },
            "assignedIssues": { "nodes": [] }
          },
          "errors": [
            {
              "type": "FORBIDDEN",
              "path": ["orgAccessProbe"],
              "message": "Resource protected by organization SAML enforcement.",
              "extensions": { "saml_failure": true }
            }
          ]
        }
        """
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        ))

        let client = makeClient()
        let result = try await client.fetchInbox(for: testNamespace)

        #expect(result.restriction != nil)
        #expect(result.snapshot.authoredPRs.isEmpty)
        #expect(result.snapshot.reviewRequestedPRs.isEmpty)
        #expect(result.snapshot.assignedIssues.isEmpty)
    }

    @Test("Non-SAML errors array throws graphQLErrors")
    func nonSAMLErrorsThrow() async throws {
        defer { StubURLProtocol.reset() }
        let body = """
        {
          "data": null,
          "errors": [
            { "type": "NOT_FOUND", "message": "Could not resolve to a User with the login of 'nope'." }
          ]
        }
        """
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        ))

        let client = makeClient()
        do {
            _ = try await client.fetchInbox(for: testNamespace)
            Testing.Issue.record("Expected fetchInbox to throw on non-SAML errors")
        } catch let error as GitHubError {
            guard case .graphQLErrors = error else {
                Testing.Issue.record("Expected .graphQLErrors, got \(error)")
                return
            }
        }
    }

    @Test("OAuth App access restriction (FORBIDDEN, saml_failure false) is NOT treated as SAML and throws")
    func oauthAppRestrictionIsNotSAML() async throws {
        defer { StubURLProtocol.reset() }
        // Same FORBIDDEN type as SAML but saml_failure:false and a different
        // message. Must not produce an SSO restriction; must fail the fetch.
        let body = """
        {
          "data": null,
          "errors": [
            {
              "type": "FORBIDDEN",
              "message": "Although you appear to have the correct authorization credentials, the acme organization has enabled OAuth App access restrictions, meaning that data access to third-parties is limited.",
              "extensions": { "saml_failure": false }
            }
          ]
        }
        """
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        ))

        let client = makeClient()
        do {
            _ = try await client.fetchInbox(for: testNamespace)
            Testing.Issue.record("Expected fetchInbox to throw on a non-SAML FORBIDDEN")
        } catch let error as GitHubError {
            guard case .graphQLErrors = error else {
                Testing.Issue.record("Expected .graphQLErrors, got \(error)")
                return
            }
        }
    }

    @Test("Happy path: data, no errors, no header yields PRs and no restriction")
    func happyPathNoRestriction() async throws {
        defer { StubURLProtocol.reset() }
        let body = """
        {
          "data": {
            "authored": {
              "nodes": [
                {
                  "__typename": "PullRequest",
                  "id": "PR_9",
                  "number": 9,
                  "title": "Normal PR",
                  "url": "https://github.com/acme/repo/pull/9",
                  "updatedAt": "2026-01-01T00:00:00Z",
                  "repository": { "nameWithOwner": "acme/repo" }
                }
              ]
            },
            "reviewRequested": { "nodes": [] },
            "assignedIssues": { "nodes": [] }
          }
        }
        """
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(body.utf8)
        ))

        let result = try await makeClient().fetchInbox(for: testNamespace)

        #expect(result.restriction == nil)
        #expect(result.snapshot.authoredPRs.count == 1)
        #expect(result.snapshot.authoredPRs.first?.title == "Normal PR")
    }

    @Test("Org namespace sends the org-access probe variable")
    func orgNamespaceSendsProbe() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(emptySuccessBody.utf8)
        ))

        _ = try await makeClient().fetchInbox(for: testNamespace) // .org

        let variables = try sentVariables()
        #expect(variables["includeOrgProbe"] as? Bool == true)
        #expect(variables["owner"] as? String == "acme")
        #expect(try sentQuery().contains("orgAccessProbe"))
    }

    @Test("User namespace omits the org-access probe")
    func userNamespaceOmitsProbe() async throws {
        defer { StubURLProtocol.reset() }
        StubURLProtocol.setStub(.init(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: Data(emptySuccessBody.utf8)
        ))
        let userNamespace = Namespace(
            host: "github.com",
            accountLogin: "octocat",
            owner: "octocat",
            kind: .user
        )

        _ = try await makeClient().fetchInbox(for: userNamespace)

        let variables = try sentVariables()
        #expect(variables["includeOrgProbe"] as? Bool == false)
        #expect(variables["owner"] as? String == "octocat")
    }

    // MARK: - Helpers

    private var emptySuccessBody: String {
        """
        {
          "data": {
            "authored": { "nodes": [] },
            "reviewRequested": { "nodes": [] },
            "assignedIssues": { "nodes": [] }
          }
        }
        """
    }

    private func sentRequestJSON() throws -> [String: Any] {
        let body = try #require(StubURLProtocol.capturedRequestBody())
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func sentVariables() throws -> [String: Any] {
        try #require(try sentRequestJSON()["variables"] as? [String: Any])
    }

    private func sentQuery() throws -> String {
        try #require(try sentRequestJSON()["query"] as? String)
    }
}
