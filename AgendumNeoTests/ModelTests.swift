import Testing
import Foundation
@testable import AgendumNeo

@Suite("Model")
struct ModelTests {

    @Test("Namespace id format")
    func namespaceIDFormat() {
        let ns = Namespace(
            host: "github.com",
            accountLogin: "danseely",
            owner: "adadaptedinc",
            kind: .org
        )
        #expect(ns.id == "github.com/danseely/adadaptedinc")
        #expect(ns.displayName == "adadaptedinc")
    }

    @Test("Authored PR status reflects reviewers and reviews")
    func authoredPRStatusDerivation() {
        #expect(PullRequest.deriveAuthoredStatus(reviewRequestCount: 0, reviewCount: 0) == .open)
        #expect(PullRequest.deriveAuthoredStatus(reviewRequestCount: 2, reviewCount: 0) == .waitingForReview)
        #expect(PullRequest.deriveAuthoredStatus(reviewRequestCount: 1, reviewCount: 3) == .reviewReceived)
        #expect(PullRequest.deriveAuthoredStatus(reviewRequestCount: 0, reviewCount: 1) == .reviewReceived)
    }

    @Test("Issue status distinguishes authored from assigned")
    func issueStatusDerivation() {
        #expect(Issue.deriveStatus(authorLogin: "danseely", viewerLogin: "danseely") == .open)
        #expect(Issue.deriveStatus(authorLogin: "DanSeely", viewerLogin: "danseely") == .open)
        #expect(Issue.deriveStatus(authorLogin: "someoneElse", viewerLogin: "danseely") == .assignedToYou)
        #expect(Issue.deriveStatus(authorLogin: "anyone", viewerLogin: nil) == .assignedToYou)
        #expect(Issue.deriveStatus(authorLogin: "anyone", viewerLogin: "") == .assignedToYou)
    }

    @Test("Author display uses first GitHub display-name token")
    func authorDisplayUsesFirstDisplayNameToken() {
        #expect(GitHubAuthorDisplayName.firstName(name: "Dan Seely", login: "danseely") == "Dan")
        #expect(GitHubAuthorDisplayName.firstName(name: "  Dana  Scully  ", login: "dscully") == "Dana")
    }

    @Test("Author display falls back to login")
    func authorDisplayFallsBackToLogin() {
        #expect(GitHubAuthorDisplayName.firstName(name: nil, login: "danseely") == "danseely")
        #expect(GitHubAuthorDisplayName.firstName(name: "   ", login: "danseely") == "danseely")
        #expect(GitHubAuthorDisplayName.firstName(name: nil, login: nil) == "")
    }

    @Test("GH CLI missing message is actionable")
    func ghCLIMissingMessage() {
        let message = "gh not found in PATH. Install via Homebrew or run from a terminal."
        #expect(String(describing: GHCLIError.ghNotInstalled) == message)
        #expect(GHCLIError.ghNotInstalled.localizedDescription == message)
    }

    @Test("GH CLI search path covers common Mac install locations")
    func ghCLISearchPath() {
        let components = GHCLI.ghSearchPath.split(separator: ":").map(String.init)
        #expect(components == ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
    }

    @Test("GH CLI environment preserves auth context")
    func ghCLIEnvironmentPreservesAuthContext() {
        let environment = GHCLI.ghProcessEnvironment(base: [
            "HOME": "/Users/tester",
            "GH_CONFIG_DIR": "/Users/tester/.config/gh",
            "PATH": "/custom/bin"
        ])

        #expect(environment["PATH"] == GHCLI.ghSearchPath)
        #expect(environment["HOME"] == "/Users/tester")
        #expect(environment["GH_CONFIG_DIR"] == "/Users/tester/.config/gh")
    }
}

@Suite("Sync status label")
struct SyncStatusLabelTests {
    private let synced = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Zero seconds elapsed reads as just now")
    func zeroSecondsJustNow() {
        let now = synced
        #expect(SyncStatusLabel.text(synced: synced, now: now) == "Synced just now")
    }

    @Test("Thirty seconds elapsed reads as just now")
    func thirtySecondsJustNow() {
        let now = synced.addingTimeInterval(30)
        #expect(SyncStatusLabel.text(synced: synced, now: now) == "Synced just now")
    }

    @Test("Fifty-nine seconds elapsed reads as just now")
    func fiftyNineSecondsJustNow() {
        let now = synced.addingTimeInterval(59)
        #expect(SyncStatusLabel.text(synced: synced, now: now) == "Synced just now")
    }

    @Test("Sixty seconds elapsed reads as one minute ago")
    func sixtySecondsOneMinute() {
        let now = synced.addingTimeInterval(60)
        #expect(SyncStatusLabel.text(synced: synced, now: now) == "Synced 1 minute ago")
    }

    @Test("Ninety seconds elapsed reads as one minute ago")
    func ninetySecondsOneMinute() {
        let now = synced.addingTimeInterval(90)
        #expect(SyncStatusLabel.text(synced: synced, now: now) == "Synced 1 minute ago")
    }

    @Test("Two minutes elapsed pluralizes")
    func twoMinutesAgo() {
        let now = synced.addingTimeInterval(120)
        #expect(SyncStatusLabel.text(synced: synced, now: now) == "Synced 2 minutes ago")
    }

    @Test("Five minutes elapsed pluralizes")
    func fiveMinutesAgo() {
        let now = synced.addingTimeInterval(5 * 60)
        #expect(SyncStatusLabel.text(synced: synced, now: now) == "Synced 5 minutes ago")
    }

    @Test("Sixty minutes elapsed reads as sixty minutes ago")
    func sixtyMinutesAgo() {
        let now = synced.addingTimeInterval(60 * 60)
        #expect(SyncStatusLabel.text(synced: synced, now: now) == "Synced 60 minutes ago")
    }
}
