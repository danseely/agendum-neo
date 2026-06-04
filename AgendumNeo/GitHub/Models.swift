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

/// Lifecycle status of a row in the "Awaiting your review" section. A PR enters
/// as `.reviewRequested` (GitHub is asking for your review); once you submit
/// your review it leaves GitHub's `review-requested:@me` search, and we surface
/// it as `.reviewed` for a couple of sync cycles so the completion is visible
/// before the row drops off. See `ReviewSectionReconciler` and issue #69.
enum ReviewRowStatus: String, Sendable, Codable {
    case reviewRequested
    case reviewed
}

/// A row in the "Awaiting your review" section, pairing the underlying PR with
/// its review-section lifecycle state. `syncsRemaining` is only meaningful for
/// `.reviewed` rows — it counts the lingering window down each sync (issue #69).
struct ReviewInboxPR: Sendable, Hashable, Codable, Identifiable {
    let pullRequest: PullRequest
    let status: ReviewRowStatus
    let syncsRemaining: Int

    var id: String { pullRequest.id }
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
    let reReviewRequested: Bool

    var authoredStatus: PRAuthoredStatus {
        Self.deriveAuthoredStatus(
            reviewDecision: reviewDecision,
            reviewRequestCount: reviewRequestCount,
            latestReviewVerdict: latestReviewVerdict,
            reReviewRequested: reReviewRequested
        )
    }

    // GitHub's `reviewDecision` already encodes the right precedence (approval
    // survives adding new reviewers, re-requesting a dismissed approver flips
    // back to REVIEW_REQUIRED), so prefer it when present. It is null on PRs
    // in repos without a branch-protection rule requiring review — in that
    // case fall back to this ordering: a re-request wins, otherwise a standing
    // verdict, otherwise a bare pending request, otherwise open. See the
    // in-body comments for the per-branch rationale (issues #41, #50, #57).
    static func deriveAuthoredStatus(
        reviewDecision: PRReviewDecision?,
        reviewRequestCount: Int,
        latestReviewVerdict: PRReviewVerdict?,
        reReviewRequested: Bool
    ) -> PRAuthoredStatus {
        switch reviewDecision {
        case .approved: return .approved
        case .changesRequested: return .changesRequested
        case .reviewRequired:
            // A re-request of someone who already reviewed means we're genuinely
            // waiting on them again (issue #41) — that beats a stale verdict.
            if reReviewRequested { return .waitingForReview }
            // Otherwise a returned COMMENTED verdict surfaces even if other (fresh)
            // reviewers are still pending — the author wants to know a review came
            // back (the Alex+Steven masking case).
            if latestReviewVerdict == .commented { return .commented }
            if reviewRequestCount > 0 { return .waitingForReview }
            return .open
        case .none:
            // Same discriminator closes #50 in unprotected repos: a re-request of a
            // prior reviewer keeps "waiting"; a new reviewer added to a PR that
            // already has a verdict lets the verdict stand.
            if reReviewRequested { return .waitingForReview }
            if let verdict = latestReviewVerdict { return verdict.authoredStatus }
            if reviewRequestCount > 0 { return .waitingForReview }
            return .open
        }
    }

    /// True when a pending review request targets someone who already has a
    /// review in `latestReviews` — a re-request (issue #41), as opposed to a
    /// brand-new reviewer who hasn't weighed in (issue #50 / #658). Used to
    /// decide whether a returned COMMENTED verdict should surface or whether we
    /// should keep waiting on the re-requested reviewer.
    static func deriveReReviewRequested(
        pendingReviewerLogins: [String],
        reviewedByLogins: [String]
    ) -> Bool {
        guard !pendingReviewerLogins.isEmpty, !reviewedByLogins.isEmpty else { return false }
        let reviewed = Set(reviewedByLogins.map { $0.lowercased() })
        return pendingReviewerLogins.contains { reviewed.contains($0.lowercased()) }
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
