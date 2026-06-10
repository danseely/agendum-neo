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

    init(host: String, token: String) {
        self.host = host
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "AgendumNeo/0.1 (+local)",
            "Accept": "application/vnd.github+json"
        ]
        self.session = URLSession(configuration: config)
        self.endpoint = Self.graphqlEndpoint(for: host)
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
        let variables: [String: String] = [
            "authored": "is:open is:pr author:@me user:\(owner) archived:false",
            "reviewReq": "is:open is:pr review-requested:@me user:\(owner) archived:false",
            "issues": "is:open is:issue assignee:@me user:\(owner) archived:false"
        ]
        let body: [String: Any] = [
            "query": Queries.inbox,
            "variables": variables
        ]
        let result: PostResult<InboxData> = try await post(body: body)
        let envelope = result.envelope
        if let errs = envelope.errors, !errs.isEmpty {
            throw GitHubError.graphQLErrors(errs.map(\.message))
        }
        guard let payload = envelope.data else {
            throw GitHubError.decoding("missing data")
        }

        let authored = payload.authored.nodes.compactMap { $0.toPullRequest() }
        let reviewRequested = payload.reviewRequested.nodes.compactMap { $0.toPullRequest() }
        let issues = payload.assignedIssues.nodes.compactMap { $0.toIssue() }

        let snapshot = InboxSnapshot(
            namespace: namespace,
            fetchedAt: Date(),
            authoredPRs: authored,
            reviewRequestedPRs: reviewRequested,
            assignedIssues: issues
        )
        // An SSO-unauthorized token silently drops the org's search results and
        // tags the response with `X-GitHub-SSO`. Surface it so the empty inbox
        // reads as "authorize your token", not "you have no PRs".
        return InboxResult(
            snapshot: snapshot,
            restriction: AccessRestriction.parse(ssoHeader: result.ssoHeader)
        )
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

        // GraphQL returns 200 with partial data when an SSO-protected org is
        // dropped from the results; the only signal is this header.
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
