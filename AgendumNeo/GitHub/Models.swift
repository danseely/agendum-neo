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

    var authoredStatus: PRAuthoredStatus {
        switch self {
        case .approved: return .approved
        case .changesRequested: return .changesRequested
        case .commented: return .commented
        }
    }
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

// Mirrors GitHub's PullRequestReviewDecision enum. Null when the repo has no
// branch-protection rule requiring review, in which case we fall back to the
// verdict + request-count heuristic.
enum PRReviewDecision: String, Sendable, Codable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
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
    let reviewDecision: PRReviewDecision?

    var authoredStatus: PRAuthoredStatus {
        Self.deriveAuthoredStatus(
            reviewDecision: reviewDecision,
            reviewRequestCount: reviewRequestCount,
            latestReviewVerdict: latestReviewVerdict
        )
    }

    // GitHub's `reviewDecision` already encodes the right precedence (approval
    // survives adding new reviewers, re-requesting a dismissed approver flips
    // back to REVIEW_REQUIRED), so prefer it when present. It is null on PRs
    // in repos without a branch-protection rule requiring review — in that
    // case fall back to a pending-request-wins heuristic so issue #41
    // (re-request after a prior verdict) still reads as "waiting".
    static func deriveAuthoredStatus(
        reviewDecision: PRReviewDecision?,
        reviewRequestCount: Int,
        latestReviewVerdict: PRReviewVerdict?
    ) -> PRAuthoredStatus {
        switch reviewDecision {
        case .approved: return .approved
        case .changesRequested: return .changesRequested
        case .reviewRequired:
            // Required review not yet satisfied. A pending request means we're
            // actively waiting on someone; a commented verdict surfaces that
            // people are engaging. With neither, the PR is still open — branch
            // protection just hasn't been satisfied yet, but no one is "late".
            if reviewRequestCount > 0 { return .waitingForReview }
            if let verdict = latestReviewVerdict { return verdict.authoredStatus }
            return .open
        case .none:
            if reviewRequestCount > 0 { return .waitingForReview }
            return latestReviewVerdict?.authoredStatus ?? .open
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
