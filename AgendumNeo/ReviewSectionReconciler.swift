import Foundation

/// Reconciles the previously-displayed "Awaiting your review" section with a
/// freshly-fetched set of review-requested PRs.
///
/// GitHub drops a PR from `review-requested:@me` the moment you submit your
/// review, so a reviewed item would otherwise vanish from the inbox with no
/// acknowledgement. To make the completion visible (issue #69) we keep a PR
/// that *was* awaiting your review but has now left the requested set, mark it
/// `.reviewed`, and linger it for `lingerSyncs` sync cycles before it drops off.
enum ReviewSectionReconciler {
    /// How many sync cycles a reviewed PR lingers after it leaves the requested
    /// set. At the default 5-minute poll interval two cycles is roughly ten
    /// minutes on screen — long enough to notice, short enough to stay tidy.
    static let lingerSyncs = 2

    /// Merge `fetched` (the fresh `review-requested:@me` result) with the rows
    /// shown last sync. Active requests come straight from `fetched`; rows that
    /// have dropped out are presumed reviewed-by-you and carried as `.reviewed`
    /// with a decrementing countdown. Order is stable: live requests first,
    /// lingering reviewed rows after, each group preserving input order.
    static func reconcile(
        previous: [ReviewInboxPR],
        fetched: [PullRequest]
    ) -> [ReviewInboxPR] {
        let fetchedIDs = Set(fetched.map(\.id))

        // Fresh review requests always win. A lingering `.reviewed` PR that gets
        // re-requested reappears in `fetched` and flips back to requested here.
        var rows = fetched.map {
            ReviewInboxPR(pullRequest: $0, status: .reviewRequested, syncsRemaining: 0)
        }

        // Rows that were on the list but have left the requested set are
        // presumed reviewed-by-you. A `.reviewRequested` row just transitioned
        // this sync (start a fresh window); a `.reviewed` row counts down and
        // drops when the window expires.
        for item in previous where !fetchedIDs.contains(item.id) {
            let remaining: Int
            switch item.status {
            case .reviewRequested:
                remaining = lingerSyncs
            case .reviewed:
                remaining = item.syncsRemaining - 1
            }
            guard remaining > 0 else { continue }
            rows.append(ReviewInboxPR(
                pullRequest: item.pullRequest,
                status: .reviewed,
                syncsRemaining: remaining
            ))
        }
        return rows
    }
}
