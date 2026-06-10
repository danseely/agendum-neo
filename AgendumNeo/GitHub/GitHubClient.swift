import Foundation
import os

private let decoderLog = Logger(
    subsystem: "net.danseely.AgendumNeo",
    category: "GitHubDecoder"
)

enum GitHubError: Error, Sendable {
    case httpStatus(Int, body: String)
    case graphQLErrors([String])
    case decoding(String)
}

actor GitHubClient {
    private let host: String
    private let token: String
    private let session: URLSession
    private let endpoint: URL

    /// - Parameter session: Injectable for tests so a `URLProtocol`-backed
    ///   session can stub responses. Defaults to the production ephemeral
    ///   session, preserving existing behavior.
    init(host: String, token: String, session: URLSession? = nil) {
        self.host = host
        self.token = token
        self.session = session ?? Self.makeDefaultSession()
        self.endpoint = Self.graphqlEndpoint(for: host)
    }

    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "AgendumNeo/0.1 (+local)",
            "Accept": "application/vnd.github+json"
        ]
        return URLSession(configuration: config)
    }

    func fetchNamespaces(forAccount account: GHAccount) async throws -> [Namespace] {
        let body: [String: Any] = ["query": Queries.namespaces]
        let envelope: GraphQLEnvelope<NamespacesData> = try await post(body: body).envelope
        if let errs = envelope.errors, !errs.isEmpty {
            throw GitHubError.graphQLErrors(errs.map(\.message))
        }
        guard let payload = envelope.data else {
            throw GitHubError.decoding("missing data")
        }
        let user = Namespace(
            host: account.host,
            accountLogin: account.login,
            owner: payload.viewer.login,
            kind: .user
        )
        let orgs = payload.viewer.organizations.nodes.map { node in
            Namespace(
                host: account.host,
                accountLogin: account.login,
                owner: node.login,
                kind: .org
            )
        }
        return [user] + orgs.sorted { $0.owner.localizedCaseInsensitiveCompare($1.owner) == .orderedAscending }
    }

    func fetchInbox(for namespace: Namespace) async throws -> InboxResult {
        let owner = namespace.owner
        // The org-access probe only makes sense for org namespaces;
        // `organization(login:)` against a personal account 404s. `@include`
        // drops the field entirely when this is false (see Queries.inbox).
        let variables: [String: Any] = [
            "authored": "is:open is:pr author:@me user:\(owner) archived:false",
            "reviewReq": "is:open is:pr review-requested:@me user:\(owner) archived:false",
            "issues": "is:open is:issue assignee:@me user:\(owner) archived:false",
            "owner": owner,
            "includeOrgProbe": namespace.kind == .org
        ]
        let body: [String: Any] = [
            "query": Queries.inbox,
            "variables": variables
        ]
        let result: PostResult<InboxData> = try await post(body: body)
        let envelope = result.envelope

        // The header-parsed restriction (when present), used as the baseline and
        // also as a richer fallback for the errors-array SAML path below.
        let headerRestriction = AccessRestriction.parse(ssoHeader: result.ssoHeader)

        // An SSO-unauthorized token can surface a SAML restriction in a few
        // shapes, all HTTP 200: (a) a non-empty GraphQL `errors` array with
        // `FORBIDDEN` / `extensions.saml_failure` — alongside PARTIAL `data`
        // (the accessible results) per the real `gh status` behavior — or (b)
        // empty/absent `data` carrying just the `X-GitHub-SSO` header. We keep
        // whatever data did come back and attach the restriction rather than
        // throwing, so a partly-visible org still renders its visible rows.
        var samlRestriction: AccessRestriction?
        if let errs = envelope.errors, !errs.isEmpty {
            if Self.errorsIndicateSAML(errs) {
                // Prefer the header restriction when it carries an authorization
                // URL; otherwise fall back to `.ssoRequired` carrying whatever
                // URL the header yielded (may be nil).
                if let headerRestriction, headerRestriction.authorizationURL != nil {
                    samlRestriction = headerRestriction
                } else {
                    samlRestriction = .ssoRequired(url: headerRestriction?.authorizationURL)
                }
            } else {
                // Genuine, non-SAML errors still fail the fetch.
                throw GitHubError.graphQLErrors(errs.map(\.message))
            }
        }

        // Build the snapshot from whatever `data` arrived. Under SAML this is
        // the partial (possibly empty) set; on the happy path it's the full set.
        let snapshot: InboxSnapshot
        if let payload = envelope.data {
            snapshot = InboxSnapshot(
                namespace: namespace,
                fetchedAt: Date(),
                authoredPRs: payload.authored.nodes.compactMap { $0.toPullRequest() },
                reviewRequestedPRs: payload.reviewRequested.nodes.compactMap { $0.toPullRequest() },
                assignedIssues: payload.assignedIssues.nodes.compactMap { $0.toIssue() }
            )
        } else if samlRestriction != nil {
            // SAML blocked the whole query and returned no data — empty inbox,
            // restriction surfaces the reason instead of a blank list.
            snapshot = InboxSnapshot(
                namespace: namespace,
                fetchedAt: Date(),
                authoredPRs: [],
                reviewRequestedPRs: [],
                assignedIssues: []
            )
        } else {
            throw GitHubError.decoding("missing data")
        }

        // SAML-from-errors wins (it's the authoritative signal); otherwise fall
        // back to the header (the silent-empty case).
        return InboxResult(snapshot: snapshot, restriction: samlRestriction ?? headerRestriction)
    }

    private func post<T: Decodable>(body: [String: Any]) async throws -> PostResult<T> {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.httpStatus(-1, body: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let preview = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.httpStatus(http.statusCode, body: preview)
        }

        // Captured for SSO detection. On GraphQL the authoritative SAML signal
        // is the `errors` array (see `fetchInbox`); this header is a secondary,
        // not-always-present hint that also carries an authorization URL.
        let ssoHeader = http.value(forHTTPHeaderField: "X-GitHub-SSO")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let envelope = try decoder.decode(GraphQLEnvelope<T>.self, from: data)
            return PostResult(envelope: envelope, ssoHeader: ssoHeader)
        } catch {
            throw GitHubError.decoding(String(describing: error))
        }
    }

    private static func graphqlEndpoint(for host: String) -> URL {
        if host == "github.com" {
            return URL(string: "https://api.github.com/graphql")!
        }
        return URL(string: "https://\(host)/api/graphql")!
    }
}

/// A fetched inbox plus any non-fatal access restriction detected on the
/// response (e.g. an SSO-unauthorized org that silently dropped its results).
struct InboxResult: Sendable {
    let snapshot: InboxSnapshot
    let restriction: AccessRestriction?
}

// MARK: - Wire types

/// A decoded GraphQL envelope paired with the response's `X-GitHub-SSO` header
/// (nil when absent), so callers can detect silent SSO result-dropping.
private struct PostResult<T: Decodable> {
    let envelope: GraphQLEnvelope<T>
    let ssoHeader: String?
}

private struct GraphQLEnvelope<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
    let type: String?
    let extensions: Extensions?

    struct Extensions: Decodable {
        let samlFailure: Bool

        private enum CodingKeys: String, CodingKey {
            case samlFailure = "saml_failure"
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.samlFailure = (try c.decodeIfPresent(Bool.self, forKey: .samlFailure)) ?? false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case message, type, extensions
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try c.decode(String.self, forKey: .message)
        self.type = try c.decodeIfPresent(String.self, forKey: .type)
        self.extensions = try c.decodeIfPresent(Extensions.self, forKey: .extensions)
    }

    /// True when this error indicates a SAML SSO restriction: either GitHub
    /// flagged it explicitly via `extensions.saml_failure`, or it is a
    /// FORBIDDEN error whose message mentions SAML.
    var indicatesSAML: Bool {
        if extensions?.samlFailure == true { return true }
        if type == "FORBIDDEN", message.range(of: "SAML", options: .caseInsensitive) != nil {
            return true
        }
        return false
    }
}

extension GitHubClient {
    /// Whether a GraphQL `errors` array signals a SAML SSO restriction (vs a
    /// genuine error that should be thrown). `fileprivate` because it takes the
    /// private wire type; exercised end-to-end through `fetchInbox` (see the
    /// SSO tests stubbing a `URLProtocol`).
    fileprivate static func errorsIndicateSAML(_ errors: [GraphQLError]) -> Bool {
        errors.contains { $0.indicatesSAML }
    }
}

private struct NamespacesData: Decodable {
    let viewer: Viewer
    struct Viewer: Decodable {
        let login: String
        let organizations: OrgNodes
    }
    struct OrgNodes: Decodable {
        let nodes: [OrgNode]
    }
    struct OrgNode: Decodable {
        let login: String
    }
}

private struct InboxData: Decodable {
    let authored: SearchNodes<SearchNode>
    let reviewRequested: SearchNodes<SearchNode>
    let assignedIssues: SearchNodes<SearchNode>
}

private struct SearchNodes<Node: Decodable>: Decodable {
    let nodes: [Node]
}

private struct SearchNode: Decodable {
    let typename: String
    let id: String?
    let number: Int?
    let title: String?
    let url: URL?
    let updatedAt: Date?
    let isDraft: Bool?
    let authorLogin: String?
    let authorName: String?
    let repository: String?
    let reviewRequestsTotal: Int?
    let pendingReviewerLogins: [String]
    let latestReviewStates: [PRReviewState]
    let reviewedByLogins: [String]
    let reviewDecision: PRReviewDecision?

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case id, number, title, url, updatedAt, isDraft, author, repository, reviewRequests, latestReviews, reviewDecision
    }

    private struct AuthorBox: Decodable {
        let login: String?
        let name: String?
    }
    private struct RepoBox: Decodable { let nameWithOwner: String }
    private struct AuthorLoginBox: Decodable { let login: String? }
    // `PullRequestReview.state` is NON_NULL in the GraphQL schema; a null
    // would indicate a server/schema break and should fail the decode loudly.
    private struct ReviewNodeBox: Decodable {
        let state: String
        let author: AuthorLoginBox?
    }
    private struct ReviewListBox: Decodable { let nodes: [ReviewNodeBox]? }
    // Only User reviewers carry a `login`. Team / Bot / Mannequin requested
    // reviewers have no User login and are intentionally treated as "new
    // pending" rather than re-requests (per issue #50) — they can't appear in
    // `latestReviews` author logins, so the re-request cross-reference will
    // never match them by construction.
    private struct RequestedReviewerBox: Decodable {
        let typename: String
        let login: String?   // present only for User
        enum CodingKeys: String, CodingKey { case typename = "__typename", login }
    }
    private struct ReviewRequestNodeBox: Decodable { let requestedReviewer: RequestedReviewerBox? }
    private struct ReviewRequestsBox: Decodable {
        let totalCount: Int
        let nodes: [ReviewRequestNodeBox]?
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.typename = try c.decode(String.self, forKey: .typename)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.number = try c.decodeIfPresent(Int.self, forKey: .number)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.url = try c.decodeIfPresent(URL.self, forKey: .url)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.isDraft = try c.decodeIfPresent(Bool.self, forKey: .isDraft)
        let author = try c.decodeIfPresent(AuthorBox.self, forKey: .author)
        self.authorLogin = author?.login
        self.authorName = author?.name
        self.repository = (try c.decodeIfPresent(RepoBox.self, forKey: .repository))?.nameWithOwner
        let reviewRequests = try c.decodeIfPresent(ReviewRequestsBox.self, forKey: .reviewRequests)
        self.reviewRequestsTotal = reviewRequests?.totalCount
        // Only User reviewers feed the re-request cross-reference; Team / Bot /
        // Mannequin requests fall through as "new pending" (issue #50).
        self.pendingReviewerLogins = reviewRequests?.nodes?.compactMap { node in
            guard let reviewer = node.requestedReviewer, reviewer.typename == "User" else { return nil }
            return reviewer.login
        } ?? []
        let reviews = try c.decodeIfPresent(ReviewListBox.self, forKey: .latestReviews)
        // Unknown raw states (future GitHub additions) are skipped rather than failing the decode.
        // `latestReviewStates` and `reviewedByLogins` are derived from the same filtered node set
        // so a node whose raw state doesn't decode can't contribute a login (feeding the
        // re-request cross-reference) without also contributing a verdict — avoids future drift
        // where a half-counted reviewer flips the authored status. DISMISSED is a known state and
        // is kept here (the dismissed-then-re-requested case still needs to read as "waiting").
        let decodedReviewNodes = reviews?.nodes?.compactMap { node -> (PRReviewState, String?)? in
            guard let state = PRReviewState(rawValue: node.state) else { return nil }
            return (state, node.author?.login)
        } ?? []
        self.latestReviewStates = decodedReviewNodes.map { $0.0 }
        self.reviewedByLogins = decodedReviewNodes.compactMap { $0.1 }
        // reviewDecision is nullable in the schema (e.g. no required-review
        // branch protection); an unknown future raw value falls back to nil
        // and is logged so a silent mis-render against a new GitHub state
        // shows up under the GitHubDecoder logging category.
        let rawDecision = try c.decodeIfPresent(String.self, forKey: .reviewDecision)
        let decoded = rawDecision.flatMap { PRReviewDecision(rawValue: $0) }
        if let raw = rawDecision, decoded == nil {
            decoderLog.warning("Unknown PullRequest.reviewDecision raw value from GitHub: \(raw, privacy: .public)")
        }
        self.reviewDecision = decoded
    }

    func toPullRequest() -> PullRequest? {
        guard
            typename == "PullRequest",
            let id, let number, let title, let url, let updatedAt,
            let repository
        else { return nil }
        return PullRequest(
            id: id,
            number: number,
            title: title,
            url: url,
            repository: repository,
            author: GitHubAuthorDisplayName.firstName(name: authorName, login: authorLogin),
            isDraft: isDraft ?? false,
            updatedAt: updatedAt,
            reviewRequestCount: reviewRequestsTotal ?? 0,
            latestReviewVerdict: PullRequest.deriveReviewVerdict(latestReviewStates: latestReviewStates),
            reviewDecision: reviewDecision,
            reReviewRequested: PullRequest.deriveReReviewRequested(
                pendingReviewerLogins: pendingReviewerLogins,
                reviewedByLogins: reviewedByLogins
            )
        )
    }

    func toIssue() -> Issue? {
        guard
            typename == "Issue",
            let id, let number, let title, let url, let updatedAt,
            let repository
        else { return nil }
        return Issue(
            id: id,
            number: number,
            title: title,
            url: url,
            repository: repository,
            author: GitHubAuthorDisplayName.firstName(name: authorName, login: authorLogin),
            authorLogin: authorLogin ?? "",
            updatedAt: updatedAt
        )
    }
}
