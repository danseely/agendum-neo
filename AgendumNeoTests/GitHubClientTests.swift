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

        func set(_ value: Stub?) {
            lock.lock(); defer { lock.unlock() }
            stub = value
        }

        func get() -> Stub? {
            lock.lock(); defer { lock.unlock() }
            return stub
        }
    }

    private static let box = Box()

    static func setStub(_ stub: Stub) { box.set(stub) }
    static func reset() { box.set(nil) }
    private static func currentStub() -> Stub? { box.get() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
}
