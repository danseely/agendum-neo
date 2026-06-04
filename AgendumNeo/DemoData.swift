import Foundation

enum DemoData {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("--demo")
    }

    static let namespaces: [Namespace] = [
        Namespace(host: "github.com", accountLogin: "danseely", owner: "danseely", kind: .user),
        Namespace(host: "github.com", accountLogin: "danseely", owner: "acme-corp", kind: .org),
        Namespace(host: "github.com", accountLogin: "danseely", owner: "agendum-labs", kind: .org)
    ]

    // Curated so every status pill variant renders at least once:
    //   Your PRs        — Open, Waiting for review, Approved, Changes requested,
    //                     Commented, plus the DRAFT badge
    //   Awaiting review — Review requested (incl. one draft); the lingering
    //                     "Reviewed" row is added by `reviewSection(for:)`.
    //   Assigned issues — Open (viewer-authored) and Assigned to you
    // The tricky review-state scenarios from issues #41, #50, and #57 are kept
    // as live fixtures — see the per-row comments.
    static func snapshot(for namespace: Namespace) -> InboxSnapshot {
        let now = Date()

        let viewerLogin = namespace.accountLogin
        let owner = namespace.owner

        let authoredPRs: [PullRequest] = [
            pr(1, 164, "Add keyboard shortcut cheat-sheet overlay",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 0.5, reqs: 0, verdict: nil, decision: nil),
            pr(2, 161, "Stream sync deltas instead of full snapshots",
               owner: owner, repo: "platform-api", author: "Dan",
               draft: false, hoursAgo: 3, reqs: 2, verdict: nil, decision: .reviewRequired),
            pr(3, 158, "Adopt Liquid Glass material in the menu bar popover",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 7, reqs: 0, verdict: .approved, decision: .approved),
            pr(4, 154, "Spike: live PR-count badge on the Dock icon",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: true, hoursAgo: 12, reqs: 0, verdict: nil, decision: nil),
            pr(5, 151, "Cache GraphQL responses on disk between launches",
               owner: owner, repo: "ingest-pipeline", author: "Dan",
               draft: false, hoursAgo: 19, reqs: 0, verdict: .changesRequested, decision: .changesRequested),
            pr(6, 147, "Tighten retry backoff on flaky network paths",
               owner: owner, repo: "search-service", author: "Dan",
               draft: false, hoursAgo: 25, reqs: 0, verdict: .commented, decision: .reviewRequired),
            // Demos issue #41: a re-request after a dismissed approval. GitHub
            // flips reviewDecision back to REVIEW_REQUIRED so we read "Waiting"
            // despite a prior approval still being in latestReviews.
            pr(7, 143, "Migrate snapshot persistence to SwiftData",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 31, reqs: 1, verdict: .approved, decision: .reviewRequired,
               reReview: true),
            // Demos PR #658-style scenario: an already-approved PR with a fresh
            // review requested from an additional reviewer. reviewDecision stays
            // APPROVED, so we keep showing "Approved" rather than reverting.
            pr(8, 139, "Bump GraphQL schema version and regenerate types",
               owner: owner, repo: "platform-api", author: "Dan",
               draft: false, hoursAgo: 38, reqs: 1, verdict: .approved, decision: .approved),
            // Demos issue #57: a reviewer left a COMMENTED review while a
            // *different* reviewer is still pending. The pending reviewer never
            // reviewed, so reReviewRequested is false and the pill surfaces
            // "Commented" rather than masking it as "Waiting for review".
            pr(9, 136, "Dedupe notification fan-out in the worker pool",
               owner: owner, repo: "ingest-pipeline", author: "Dan",
               draft: false, hoursAgo: 46, reqs: 1, verdict: .commented, decision: .reviewRequired,
               reReview: false),
            // Demos issue #50: an unprotected repo where a new (different)
            // reviewer was added to an already-approved PR. reviewDecision is
            // null, but reReviewRequested is false so the verdict wins and we
            // render "Approved".
            pr(10, 132, "Polish onboarding copy for the empty inbox",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 53, reqs: 1, verdict: .approved, decision: nil,
               reReview: false)
        ]

        let reviewRequestedPRs: [PullRequest] = [
            pr(101, 233, "Roll session tokens without dropping live syncs",
               owner: owner, repo: "platform-api", author: "Alice",
               draft: false, hoursAgo: 1.5, reqs: 1, verdict: nil, decision: .reviewRequired),
            pr(102, 229, "Shard the search index by namespace",
               owner: owner, repo: "search-service", author: "Priya",
               draft: false, hoursAgo: 8, reqs: 1, verdict: nil, decision: .reviewRequired),
            pr(103, 226, "Queue-depth autoscaling for ingest workers",
               owner: owner, repo: "ingest-pipeline", author: "Mei",
               draft: true, hoursAgo: 15, reqs: 1, verdict: nil, decision: .reviewRequired),
            pr(104, 222, "Replace cron reconciler with event-driven sync",
               owner: owner, repo: "platform-api", author: "Jonah",
               draft: false, hoursAgo: 23, reqs: 1, verdict: nil, decision: .reviewRequired),
            pr(105, 218, "Expose rate-limit headroom in /healthz",
               owner: owner, repo: "platform-cli", author: "Sasha",
               draft: false, hoursAgo: 35, reqs: 1, verdict: nil, decision: .reviewRequired)
        ]

        let assignedIssues: [Issue] = [
            issue(1, 61, "Menu bar count lags one sync behind the window",
                  owner: owner, repo: "agendum-neo",
                  author: "Dan", authorLogin: viewerLogin, hoursAgo: 2),
            issue(2, 58, "Namespace picker loses selection after wake from sleep",
                  owner: owner, repo: "agendum-neo",
                  author: "Carol", authorLogin: "carol", hoursAgo: 5),
            issue(3, 55, "Add an option to mute a repo from the inbox",
                  owner: owner, repo: "agendum-neo",
                  author: "Dan", authorLogin: viewerLogin, hoursAgo: 11),
            issue(4, 52, "Status pills clip at the largest accessibility text size",
                  owner: owner, repo: "agendum-neo",
                  author: "Riya", authorLogin: "riya", hoursAgo: 21),
            issue(5, 49, "Sync stalls when gh token expires mid-flight",
                  owner: owner, repo: "agendum-neo",
                  author: "Dan", authorLogin: viewerLogin, hoursAgo: 30),
            issue(6, 44, "Double-click row opens two browser tabs on Tahoe",
                  owner: owner, repo: "agendum-neo",
                  author: "Tomas", authorLogin: "tomas", hoursAgo: 41)
        ]

        return InboxSnapshot(
            namespace: namespace,
            fetchedAt: now,
            authoredPRs: authoredPRs,
            reviewRequestedPRs: reviewRequestedPRs,
            assignedIssues: assignedIssues
        )
    }

    /// The displayed "Awaiting your review" section for demo mode: every fetched
    /// review request plus one PR you've already reviewed, lingering for a
    /// couple of sync cycles before it drops off (issue #69). In live mode this
    /// list is produced by `ReviewSectionReconciler`; demo hand-builds it so the
    /// `Reviewed` pill renders without needing a real sync transition.
    static func reviewSection(for namespace: Namespace) -> [ReviewInboxPR] {
        let requested = snapshot(for: namespace).reviewRequestedPRs.map {
            ReviewInboxPR(pullRequest: $0, status: .reviewRequested, syncsRemaining: 0)
        }
        // A teammate's PR you reviewed last cycle — request fulfilled (reqs: 0),
        // now winding down its lingering window.
        let reviewedPR = pr(
            106, 214, "Backfill audit log for pre-migration sync runs",
            owner: namespace.owner, repo: "ingest-pipeline", author: "Devon",
            draft: false, hoursAgo: 4, reqs: 0, verdict: nil, decision: nil
        )
        let reviewed = ReviewInboxPR(
            pullRequest: reviewedPR,
            status: .reviewed,
            syncsRemaining: ReviewSectionReconciler.lingerSyncs
        )
        // Slot the lingering "Reviewed" row in as the 2nd item so the pill is
        // visible without scrolling and sits among the active requests.
        var rows = requested
        rows.insert(reviewed, at: min(1, rows.count))
        return rows
    }
}

private func pr(
    _ tag: Int,
    _ number: Int,
    _ title: String,
    owner: String,
    repo: String,
    author: String,
    draft: Bool,
    hoursAgo: Double,
    reqs: Int,
    verdict: PRReviewVerdict?,
    decision: PRReviewDecision?,
    reReview: Bool = false
) -> PullRequest {
    PullRequest(
        id: "DEMO-PR-\(tag)",
        number: number,
        title: title,
        url: URL(string: "https://github.com/\(owner)/\(repo)/pull/\(number)")!,
        repository: "\(owner)/\(repo)",
        author: author,
        isDraft: draft,
        updatedAt: Date().addingTimeInterval(-hoursAgo * 3600),
        reviewRequestCount: reqs,
        latestReviewVerdict: verdict,
        reviewDecision: decision,
        reReviewRequested: reReview
    )
}

private func issue(
    _ tag: Int,
    _ number: Int,
    _ title: String,
    owner: String,
    repo: String,
    author: String,
    authorLogin: String,
    hoursAgo: Double
) -> Issue {
    Issue(
        id: "DEMO-ISSUE-\(tag)",
        number: number,
        title: title,
        url: URL(string: "https://github.com/\(owner)/\(repo)/issues/\(number)")!,
        repository: "\(owner)/\(repo)",
        author: author,
        authorLogin: authorLogin,
        updatedAt: Date().addingTimeInterval(-hoursAgo * 3600)
    )
}
