import Foundation

struct GHAccount: Sendable, Hashable, Identifiable, Codable {
    let host: String
    let login: String
    let isActive: Bool
    var id: String { "\(host)/\(login)" }
    var displayName: String { "\(login)@\(host)" }
}

struct Namespace: Sendable, Hashable, Identifiable, Codable {
    enum Kind: String, Sendable, Codable { case user, org }
    let host: String
    let accountLogin: String
    let owner: String
    let kind: Kind
    var id: String { "\(host)/\(accountLogin)/\(owner)" }
    var displayName: String { owner }
}

enum PRAuthoredStatus: String, Sendable, Codable {
    case open
    case waitingForReview
    case approved
    case changesRequested
    case commented
}

enum PRReviewVerdict: String, Sendable, Codable {
    case approved
    case changesRequested
    case commented
}

// Mirrors GitHub's PullRequestReviewState enum. `pending` is enumerated for
// completeness but never appears in `latestReviews` (server-side filtered).
enum PRReviewState: String, Sendable, Codable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"
    case dismissed = "DISMISSED"
    case pending = "PENDING"
}

enum PRReviewStatus: String, Sendable, Codable {
    case reviewRequested
}

enum IssueStatus: String, Sendable, Codable {
    case open
    case assignedToYou
}

struct PullRequest: Sendable, Hashable, Identifiable, Codable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let author: String
    let isDraft: Bool
    let updatedAt: Date
    let reviewRequestCount: Int
    let latestReviewVerdict: PRReviewVerdict?

    var authoredStatus: PRAuthoredStatus {
        Self.deriveAuthoredStatus(
            reviewRequestCount: reviewRequestCount,
            latestReviewVerdict: latestReviewVerdict
        )
    }

    static func deriveAuthoredStatus(
        reviewRequestCount: Int,
        latestReviewVerdict: PRReviewVerdict?
    ) -> PRAuthoredStatus {
        if reviewRequestCount > 0 { return .waitingForReview }
        switch latestReviewVerdict {
        case .changesRequested: return .changesRequested
        case .approved: return .approved
        case .commented: return .commented
        case nil: return .open
        }
    }

    // CHANGES_REQUESTED beats APPROVED beats COMMENTED, matching GitHub's own
    // merge-eligibility semantics. DISMISSED reviews are ignored.
    static func deriveReviewVerdict(latestReviewStates: [PRReviewState]) -> PRReviewVerdict? {
        if latestReviewStates.contains(.changesRequested) { return .changesRequested }
        if latestReviewStates.contains(.approved) { return .approved }
        if latestReviewStates.contains(.commented) { return .commented }
        return nil
    }
}

struct Issue: Sendable, Hashable, Identifiable, Codable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repository: String
    let author: String
    let authorLogin: String
    let updatedAt: Date

    func status(viewerLogin: String?) -> IssueStatus {
        Self.deriveStatus(authorLogin: authorLogin, viewerLogin: viewerLogin)
    }

    static func deriveStatus(authorLogin: String, viewerLogin: String?) -> IssueStatus {
        guard let viewerLogin, !viewerLogin.isEmpty else { return .assignedToYou }
        return authorLogin.caseInsensitiveCompare(viewerLogin) == .orderedSame ? .open : .assignedToYou
    }
}

enum GitHubAuthorDisplayName {
    static func firstName(name: String?, login: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let firstName = trimmedName.split(whereSeparator: \.isWhitespace).first {
            return String(firstName)
        }

        return login ?? ""
    }
}

struct InboxSnapshot: Sendable, Hashable, Codable {
    let namespace: Namespace
    let fetchedAt: Date
    let authoredPRs: [PullRequest]
    let reviewRequestedPRs: [PullRequest]
    let assignedIssues: [Issue]
}
