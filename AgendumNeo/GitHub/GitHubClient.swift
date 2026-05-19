import Foundation

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
        let envelope: GraphQLEnvelope<NamespacesData> = try await post(body: body)
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

    func fetchInbox(for namespace: Namespace) async throws -> InboxSnapshot {
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
        let envelope: GraphQLEnvelope<InboxData> = try await post(body: body)
        if let errs = envelope.errors, !errs.isEmpty {
            throw GitHubError.graphQLErrors(errs.map(\.message))
        }
        guard let payload = envelope.data else {
            throw GitHubError.decoding("missing data")
        }

        let authored = payload.authored.nodes.compactMap { $0.toPullRequest() }
        let reviewRequested = payload.reviewRequested.nodes.compactMap { $0.toPullRequest() }
        let issues = payload.assignedIssues.nodes.compactMap { $0.toIssue() }

        return InboxSnapshot(
            namespace: namespace,
            fetchedAt: Date(),
            authoredPRs: authored,
            reviewRequestedPRs: reviewRequested,
            assignedIssues: issues
        )
    }

    private func post<T: Decodable>(body: [String: Any]) async throws -> GraphQLEnvelope<T> {
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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(GraphQLEnvelope<T>.self, from: data)
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

// MARK: - Wire types

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
    let latestReviewStates: [PRReviewState]
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
    private struct CountBox: Decodable { let totalCount: Int }
    // `PullRequestReview.state` is NON_NULL in the GraphQL schema; a null
    // would indicate a server/schema break and should fail the decode loudly.
    private struct ReviewNodeBox: Decodable { let state: String }
    private struct ReviewListBox: Decodable { let nodes: [ReviewNodeBox]? }

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
        self.reviewRequestsTotal = (try c.decodeIfPresent(CountBox.self, forKey: .reviewRequests))?.totalCount
        let reviews = try c.decodeIfPresent(ReviewListBox.self, forKey: .latestReviews)
        // Unknown raw states (future GitHub additions) are skipped rather than failing the decode.
        self.latestReviewStates = reviews?.nodes?.compactMap { PRReviewState(rawValue: $0.state) } ?? []
        // reviewDecision is nullable in the schema (e.g. no required-review
        // branch protection); an unknown future raw value falls back to nil.
        let rawDecision = try c.decodeIfPresent(String.self, forKey: .reviewDecision)
        self.reviewDecision = rawDecision.flatMap { PRReviewDecision(rawValue: $0) }
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
            reviewDecision: reviewDecision
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
