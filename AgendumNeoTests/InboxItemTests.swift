import Testing
import Foundation
@testable import AgendumNeo

@Suite("InboxItem")
struct InboxItemTests {

    private func makePR(
        id: String = "PR_1",
        isDraft: Bool = false,
        reviewRequestCount: Int = 0,
        latestReviewVerdict: PRReviewVerdict? = nil,
        reviewDecision: PRReviewDecision? = nil,
        reReviewRequested: Bool = false
    ) -> PullRequest {
        PullRequest(
            id: id,
            number: 42,
            title: "Sample PR",
            url: URL(string: "https://example.test/pr/42")!,
            repository: "acme-corp/widgets",
            author: "Octocat",
            isDraft: isDraft,
            updatedAt: Date(timeIntervalSince1970: 0),
            reviewRequestCount: reviewRequestCount,
            latestReviewVerdict: latestReviewVerdict,
            reviewDecision: reviewDecision,
            reReviewRequested: reReviewRequested
        )
    }

    private func makeReview(
        id: String = "PR_1",
        status: ReviewRowStatus = .reviewRequested,
        syncsRemaining: Int = 0,
        isDraft: Bool = false
    ) -> ReviewInboxPR {
        ReviewInboxPR(
            pullRequest: makePR(id: id, isDraft: isDraft),
            status: status,
            syncsRemaining: syncsRemaining
        )
    }

    private func makeIssue(id: String = "ISSUE_1") -> AgendumNeo.Issue {
        AgendumNeo.Issue(
            id: id,
            number: 99,
            title: "Sample Issue",
            url: URL(string: "https://example.test/issues/99")!,
            repository: "acme-corp/widgets",
            author: "Octocat",
            authorLogin: "octocat",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("authoredPR id matches .pr(pr.id)")
    func authoredPR_id_matchesPRItemID() {
        let pr = makePR(id: "PR_A")
        #expect(InboxItem.authoredPR(pr).id == .pr(pr.id))
    }

    @Test("reviewPR id matches .pr(pr.id)")
    func reviewPR_id_matchesPRItemID() {
        let review = makeReview(id: "PR_R")
        #expect(InboxItem.reviewPR(review).id == .pr(review.pullRequest.id))
    }

    @Test("issue id matches .issue(issue.id)")
    func issue_id_matchesIssueItemID() {
        let issue = makeIssue(id: "ISSUE_X")
        #expect(InboxItem.issue(issue, viewerLogin: nil).id == .issue(issue.id))
    }

    @Test("title and isDraftPR accessors map to the right case")
    func titleAndIsDraftAccessors() {
        let draftPR = makePR(isDraft: true)
        let nonDraftPR = makePR(isDraft: false)
        let issue = makeIssue()

        #expect(InboxItem.authoredPR(draftPR).title == draftPR.title)
        #expect(InboxItem.authoredPR(draftPR).isDraftPR == true)
        #expect(InboxItem.reviewPR(makeReview(id: nonDraftPR.id, isDraft: false)).isDraftPR == false)
        #expect(InboxItem.reviewPR(makeReview(isDraft: true)).isDraftPR == true)
        #expect(InboxItem.issue(issue, viewerLogin: nil).title == issue.title)
        #expect(InboxItem.issue(issue, viewerLogin: nil).isDraftPR == false)
    }

    // Exhaustive coverage of the statusText / statusColor switches so a new
    // PRAuthoredStatus / IssueStatus case cannot silently fall through to a
    // wrong pill in the inbox.

    @Test("authoredPR statusText covers every PRAuthoredStatus case")
    func authoredPRStatusText() {
        let open = makePR()
        let waiting = makePR(reviewRequestCount: 1)
        let approved = makePR(reviewDecision: .approved)
        let changes = makePR(reviewDecision: .changesRequested)
        let commented = makePR(latestReviewVerdict: .commented)

        // Sanity: each fixture really does derive the intended authoredStatus.
        #expect(open.authoredStatus == .open)
        #expect(waiting.authoredStatus == .waitingForReview)
        #expect(approved.authoredStatus == .approved)
        #expect(changes.authoredStatus == .changesRequested)
        #expect(commented.authoredStatus == .commented)

        #expect(InboxItem.authoredPR(open).statusText == "Open")
        #expect(InboxItem.authoredPR(waiting).statusText == "Waiting for review")
        #expect(InboxItem.authoredPR(approved).statusText == "Approved")
        #expect(InboxItem.authoredPR(changes).statusText == "Changes requested")
        #expect(InboxItem.authoredPR(commented).statusText == "Commented")
    }

    @Test("authoredPR statusColor covers every PRAuthoredStatus case")
    func authoredPRStatusColor() {
        let open = makePR()
        let waiting = makePR(reviewRequestCount: 1)
        let approved = makePR(reviewDecision: .approved)
        let changes = makePR(reviewDecision: .changesRequested)
        let commented = makePR(latestReviewVerdict: .commented)

        #expect(InboxItem.authoredPR(open).statusColor == StatusPalette.open)
        #expect(InboxItem.authoredPR(waiting).statusColor == StatusPalette.waitingForReview)
        #expect(InboxItem.authoredPR(approved).statusColor == StatusPalette.approved)
        #expect(InboxItem.authoredPR(changes).statusColor == StatusPalette.changesRequested)
        #expect(InboxItem.authoredPR(commented).statusColor == StatusPalette.commented)
    }

    @Test("reviewPR pill follows the row status, not the underlying PR state")
    func reviewPRStatus() {
        // The underlying PR's authored state shouldn't affect the review-section
        // pill — the label/color is tied to the row's ReviewRowStatus.
        let requested = ReviewInboxPR(
            pullRequest: makePR(reviewDecision: .approved),
            status: .reviewRequested,
            syncsRemaining: 0
        )
        let reviewed = ReviewInboxPR(
            pullRequest: makePR(reviewDecision: .approved),
            status: .reviewed,
            syncsRemaining: 2
        )

        #expect(InboxItem.reviewPR(requested).statusText == "Review requested")
        #expect(InboxItem.reviewPR(requested).statusColor == StatusPalette.reviewRequested)
        #expect(InboxItem.reviewPR(reviewed).statusText == "Reviewed")
        #expect(InboxItem.reviewPR(reviewed).statusColor == StatusPalette.reviewed)
    }

    @Test("issue statusText / statusColor cover every IssueStatus case")
    func issueStatus() {
        let issue = makeIssue() // authorLogin = "octocat"

        // viewer is the author → .open
        #expect(InboxItem.issue(issue, viewerLogin: "octocat").statusText == "Open")
        #expect(InboxItem.issue(issue, viewerLogin: "octocat").statusColor == StatusPalette.open)

        // viewer is somebody else → .assignedToYou
        #expect(InboxItem.issue(issue, viewerLogin: "someone-else").statusText == "Assigned to you")
        #expect(InboxItem.issue(issue, viewerLogin: "someone-else").statusColor == StatusPalette.assignedToYou)

        // No viewerLogin known → treat as .assignedToYou (matches Issue.deriveStatus).
        #expect(InboxItem.issue(issue, viewerLogin: nil).statusText == "Assigned to you")
        #expect(InboxItem.issue(issue, viewerLogin: nil).statusColor == StatusPalette.assignedToYou)
    }
}
