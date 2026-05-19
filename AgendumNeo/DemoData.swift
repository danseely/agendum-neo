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

    static func snapshot(for namespace: Namespace) -> InboxSnapshot {
        let now = Date()
        func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

        let viewerLogin = namespace.accountLogin
        let owner = namespace.owner

        let authoredPRs: [PullRequest] = [
            pr(1, 142, "Smooth out menu bar popover dismissal",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 0.75, reqs: 0, verdict: nil),
            pr(2, 141, "Refactor sync engine to a typed actor",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 4, reqs: 2, verdict: nil),
            pr(3, 138, "Improve test coverage for the GraphQL decoder",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 20, reqs: 0, verdict: .approved),
            pr(4, 133, "Spike: rate-limit handling with retry budget",
               owner: owner, repo: "ingest-pipeline", author: "Dan",
               draft: true, hoursAgo: 28, reqs: 0, verdict: nil),
            pr(5, 131, "Adopt SwiftData for cached snapshots",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 31, reqs: 0, verdict: .changesRequested),
            pr(6, 129, "Wire NSWorkspace open-URL through the new router",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 36, reqs: 3, verdict: nil),
            pr(7, 124, "Tahoe-friendly toolbar layout",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 44, reqs: 0, verdict: .commented),
            pr(8, 118, "Replace inline keys with a typed scheme",
               owner: owner, repo: "platform-cli", author: "Dan",
               draft: true, hoursAgo: 52, reqs: 0, verdict: nil),
            pr(9, 112, "Convert sync engine tests to Swift Testing",
               owner: owner, repo: "agendum-neo", author: "Dan",
               draft: false, hoursAgo: 60, reqs: 0, verdict: .approved)
        ]

        let reviewRequestedPRs: [PullRequest] = [
            pr(101, 217, "Migrate auth middleware off legacy session store",
               owner: owner, repo: "platform-api", author: "Alice",
               draft: false, hoursAgo: 2, reqs: 1, verdict: nil),
            pr(102, 215, "Drop deprecated webhook adapter",
               owner: owner, repo: "platform-api", author: "Bob",
               draft: false, hoursAgo: 9, reqs: 1, verdict: nil),
            pr(103, 213, "Lower P95 on /v2/search by 40%",
               owner: owner, repo: "search-service", author: "Priya",
               draft: false, hoursAgo: 13, reqs: 1, verdict: nil),
            pr(104, 210, "Adopt structured logging across workers",
               owner: owner, repo: "ingest-pipeline", author: "Mei",
               draft: false, hoursAgo: 18, reqs: 1, verdict: nil),
            pr(105, 208, "Cache invalidation on namespace switch",
               owner: owner, repo: "platform-api", author: "Jonah",
               draft: false, hoursAgo: 26, reqs: 1, verdict: nil),
            pr(106, 205, "Backfill retention-window field",
               owner: owner, repo: "platform-api", author: "Sasha",
               draft: false, hoursAgo: 40, reqs: 1, verdict: nil)
        ]

        let assignedIssues: [Issue] = [
            issue(1, 47, "Tokens cached past expiry on sleep/wake",
                  owner: owner, repo: "agendum-neo",
                  author: "Dan", authorLogin: viewerLogin, hoursAgo: 1.5),
            issue(2, 33, "Crash when switching namespaces during sync",
                  owner: owner, repo: "agendum-neo",
                  author: "Carol", authorLogin: "carol", hoursAgo: 6),
            issue(3, 31, "Footer 'last synced' clock drifts after sleep",
                  owner: owner, repo: "agendum-neo",
                  author: "Dan", authorLogin: viewerLogin, hoursAgo: 14),
            issue(4, 29, "DMG drag-to-Applications target hit area too small",
                  owner: owner, repo: "agendum-neo",
                  author: "Eli", authorLogin: "eli", hoursAgo: 22),
            issue(5, 27, "Add a 'reveal in Finder' affordance for the bundle",
                  owner: owner, repo: "agendum-neo",
                  author: "Dan", authorLogin: viewerLogin, hoursAgo: 33),
            issue(6, 24, "Status pills should support reduced-motion",
                  owner: owner, repo: "agendum-neo",
                  author: "Riya", authorLogin: "riya", hoursAgo: 42),
            issue(7, 21, "Investigate flaky gh-cli probe on first launch",
                  owner: owner, repo: "agendum-neo",
                  author: "Tomas", authorLogin: "tomas", hoursAgo: 55)
        ]

        return InboxSnapshot(
            namespace: namespace,
            fetchedAt: now,
            authoredPRs: authoredPRs,
            reviewRequestedPRs: reviewRequestedPRs,
            assignedIssues: assignedIssues
        )
    }

    private static func prURL(owner: String, repo: String, number: Int) -> URL {
        URL(string: "https://github.com/\(owner)/\(repo)/pull/\(number)")!
    }

    private static func issueURL(owner: String, repo: String, number: Int) -> URL {
        URL(string: "https://github.com/\(owner)/\(repo)/issues/\(number)")!
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
    verdict: PRReviewVerdict?
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
        latestReviewVerdict: verdict
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
