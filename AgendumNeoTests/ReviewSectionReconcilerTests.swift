import Testing
import Foundation
@testable import AgendumNeo

@Suite("Review section reconciler")
struct ReviewSectionReconcilerTests {

    private func pr(_ id: String) -> PullRequest {
        PullRequest(
            id: id,
            number: 1,
            title: "PR \(id)",
            url: URL(string: "https://example.test/pr/\(id)")!,
            repository: "acme-corp/widgets",
            author: "Octocat",
            isDraft: false,
            updatedAt: Date(timeIntervalSince1970: 0),
            reviewRequestCount: 1,
            latestReviewVerdict: nil,
            reviewDecision: .reviewRequired,
            reReviewRequested: false
        )
    }

    private func requested(_ id: String) -> ReviewInboxPR {
        ReviewInboxPR(pullRequest: pr(id), status: .reviewRequested, syncsRemaining: 0)
    }

    private func reviewed(_ id: String, syncsRemaining: Int) -> ReviewInboxPR {
        ReviewInboxPR(pullRequest: pr(id), status: .reviewed, syncsRemaining: syncsRemaining)
    }

    @Test("Fetched requests render as review-requested with no countdown")
    func fetchedAreRequested() {
        let rows = ReviewSectionReconciler.reconcile(
            previous: [],
            fetched: [pr("A"), pr("B")]
        )
        #expect(rows.map(\.id) == ["A", "B"])
        #expect(rows.allSatisfy { $0.status == .reviewRequested })
        #expect(rows.allSatisfy { $0.syncsRemaining == 0 })
    }

    @Test("A request that drops out of the fetch transitions to reviewed")
    func dropOutTransitionsToReviewed() {
        // Last sync showed A awaiting review; this sync A is gone (you reviewed
        // it) and B is still pending.
        let rows = ReviewSectionReconciler.reconcile(
            previous: [requested("A"), requested("B")],
            fetched: [pr("B")]
        )
        // Live requests first, lingering reviewed rows after.
        #expect(rows.map(\.id) == ["B", "A"])
        #expect(rows[0].status == .reviewRequested)
        #expect(rows[1].status == .reviewed)
        #expect(rows[1].syncsRemaining == ReviewSectionReconciler.lingerSyncs)
    }

    @Test("A reviewed row counts down each sync and drops when it expires")
    func reviewedCountsDownAndExpires() {
        // syncsRemaining == 2 → 1 (still shown)
        let firstTick = ReviewSectionReconciler.reconcile(
            previous: [reviewed("A", syncsRemaining: 2)],
            fetched: []
        )
        #expect(firstTick.map(\.id) == ["A"])
        #expect(firstTick[0].status == .reviewed)
        #expect(firstTick[0].syncsRemaining == 1)

        // syncsRemaining == 1 → 0 (dropped from the list entirely)
        let secondTick = ReviewSectionReconciler.reconcile(
            previous: [reviewed("A", syncsRemaining: 1)],
            fetched: []
        )
        #expect(secondTick.isEmpty)
    }

    @Test("A reviewed PR is displayed for exactly two sync cycles end to end")
    func reviewedLingersTwoCycles() {
        // Sync 1: A pending.
        var rows = ReviewSectionReconciler.reconcile(previous: [], fetched: [pr("A")])
        #expect(rows.map { ($0.id, $0.status) }.map(\.1) == [.reviewRequested])

        // Sync 2: A gone → reviewed (display #1).
        rows = ReviewSectionReconciler.reconcile(previous: rows, fetched: [])
        #expect(rows.count == 1 && rows[0].status == .reviewed)

        // Sync 3: still gone → reviewed (display #2).
        rows = ReviewSectionReconciler.reconcile(previous: rows, fetched: [])
        #expect(rows.count == 1 && rows[0].status == .reviewed)

        // Sync 4: window expired → gone.
        rows = ReviewSectionReconciler.reconcile(previous: rows, fetched: [])
        #expect(rows.isEmpty)
    }

    @Test("A re-requested reviewed row flips back to review-requested")
    func reRerequestFlipsBack() {
        // A is lingering as reviewed; GitHub re-requests your review (A returns
        // to the fetched set). It must read as a fresh request again.
        let rows = ReviewSectionReconciler.reconcile(
            previous: [reviewed("A", syncsRemaining: 2)],
            fetched: [pr("A")]
        )
        #expect(rows.count == 1)
        #expect(rows[0].id == "A")
        #expect(rows[0].status == .reviewRequested)
        #expect(rows[0].syncsRemaining == 0)
    }

    @Test("Empty previous and empty fetch yields an empty section")
    func emptyInputsYieldEmpty() {
        #expect(ReviewSectionReconciler.reconcile(previous: [], fetched: []).isEmpty)
    }
}
