import Testing
import Foundation
@testable import AgendumNeo

@Suite("InboxItem")
struct InboxItemTests {

    private func makePR(id: String = "PR_1", isDraft: Bool = false) -> PullRequest {
        PullRequest(
            id: id,
            number: 42,
            title: "Sample PR",
            url: URL(string: "https://example.test/pr/42")!,
            repository: "acme-corp/widgets",
            author: "Octocat",
            isDraft: isDraft,
            updatedAt: Date(timeIntervalSince1970: 0),
            reviewRequestCount: 0,
            latestReviewVerdict: nil,
            reviewDecision: nil
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

    @Test("reviewRequestedPR id matches .pr(pr.id)")
    func reviewRequestedPR_id_matchesPRItemID() {
        let pr = makePR(id: "PR_R")
        #expect(InboxItem.reviewRequestedPR(pr).id == .pr(pr.id))
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
        #expect(InboxItem.reviewRequestedPR(nonDraftPR).isDraftPR == false)
        #expect(InboxItem.issue(issue, viewerLogin: nil).title == issue.title)
        #expect(InboxItem.issue(issue, viewerLogin: nil).isDraftPR == false)
    }
}
