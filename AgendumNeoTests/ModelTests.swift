import Testing
import Foundation
import CoreGraphics
@testable import AgendumNeo

@Suite("Model")
struct ModelTests {

    @Test("Namespace id format")
    func namespaceIDFormat() {
        let ns = Namespace(
            host: "github.com",
            accountLogin: "danseely",
            owner: "acme-corp",
            kind: .org
        )
        #expect(ns.id == "github.com/danseely/acme-corp")
        #expect(ns.displayName == "acme-corp")
    }

    @Test("Authored PR status prefers GitHub reviewDecision when present")
    func authoredPRStatusUsesReviewDecision() {
        // Regression for issue with PR #658: adding a new reviewer to an
        // already-approved PR must not flip the status back to "waiting".
        // GitHub keeps reviewDecision == APPROVED in that case.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .approved,
            reviewRequestCount: 1,
            latestReviewVerdict: .approved,
            reReviewRequested: false
        ) == .approved)
        // reviewDecision dominates a stale CHANGES_REQUESTED on a latest review
        // (e.g. when GitHub considers it dismissed by branch-protection rules).
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .approved,
            reviewRequestCount: 0,
            latestReviewVerdict: .changesRequested,
            reReviewRequested: false
        ) == .approved)
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .changesRequested,
            reviewRequestCount: 0,
            latestReviewVerdict: .approved,
            reReviewRequested: false
        ) == .changesRequested)
        // Regression for issue #41: a re-request that flips reviewDecision back
        // to REVIEW_REQUIRED reads as "waiting" even if the prior approval is
        // still in latestReviews. Now disambiguated by reReviewRequested=true.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 1,
            latestReviewVerdict: .approved,
            reReviewRequested: true
        ) == .waitingForReview)
        // Row 1: REVIEW_REQUIRED with a bare pending request and no verdict
        // reads as "waiting for review" — the protected-repo baseline before
        // any reviewer has weighed in. Covers both the single-reviewer and
        // multi-reviewer shapes.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 1,
            latestReviewVerdict: nil,
            reReviewRequested: false
        ) == .waitingForReview)
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 2,
            latestReviewVerdict: nil,
            reReviewRequested: false
        ) == .waitingForReview)
        // REVIEW_REQUIRED with no pending request but a commented verdict
        // surfaces the commented state.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 0,
            latestReviewVerdict: .commented,
            reReviewRequested: false
        ) == .commented)
        // REVIEW_REQUIRED with no pending request and no verdict reads as open:
        // branch protection requires review eventually, but no one has been
        // asked and no one is "late". The author still needs to act.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 0,
            latestReviewVerdict: nil,
            reReviewRequested: false
        ) == .open)
        // REVIEW_REQUIRED with an .approved verdict but no pending request:
        // GitHub says the approval doesn't satisfy branch protection (e.g. a
        // non-CODEOWNER approved while CODEOWNER review is required). Don't
        // render the verdict — it would mislead. Fall back to .open.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 0,
            latestReviewVerdict: .approved,
            reReviewRequested: false
        ) == .open)
        // Same shape for a dismissed CHANGES_REQUESTED still visible in
        // latestReviews: the verdict no longer counts, so don't render it.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 0,
            latestReviewVerdict: .changesRequested,
            reReviewRequested: false
        ) == .open)
    }

    @Test("Authored PR status falls back to verdict + request count when reviewDecision is nil")
    func authoredPRStatusFallback() {
        // reviewDecision is null on repos without branch-protection requiring
        // review. Fall back to: re-request wins, else verdict, else pending
        // request wins, else open.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil, reviewRequestCount: 0, latestReviewVerdict: nil,
            reReviewRequested: false
        ) == .open)
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil, reviewRequestCount: 2, latestReviewVerdict: nil,
            reReviewRequested: false
        ) == .waitingForReview)
        // Re-request of a prior approver in an unprotected repo still reads
        // as "waiting" (issue #41, unprotected variant).
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil, reviewRequestCount: 1, latestReviewVerdict: .approved,
            reReviewRequested: true
        ) == .waitingForReview)
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil, reviewRequestCount: 1, latestReviewVerdict: .commented,
            reReviewRequested: true
        ) == .waitingForReview)
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil, reviewRequestCount: 0, latestReviewVerdict: .approved,
            reReviewRequested: false
        ) == .approved)
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil, reviewRequestCount: 0, latestReviewVerdict: .changesRequested,
            reReviewRequested: false
        ) == .changesRequested)
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil, reviewRequestCount: 0, latestReviewVerdict: .commented,
            reReviewRequested: false
        ) == .commented)
    }

    @Test("Authored PR status re-review disambiguation truth table (issues #57 / #50)")
    func authoredStatusReReviewDisambiguation() {
        // Row 2: Steven commented, Alex pending (different reviewer). Protected
        // repo. reReviewRequested=false → "Commented" beats the bare pending
        // request. This is the headline issue #57 masking case.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 1,
            latestReviewVerdict: .commented,
            reReviewRequested: false
        ) == .commented)

        // Row 4: #41 re-request after a COMMENTED review (protected). The
        // pending request is the original commenter, so reReviewRequested=true
        // and we keep "Waiting for review" despite the stale commented verdict.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 1,
            latestReviewVerdict: .commented,
            reReviewRequested: true
        ) == .waitingForReview)

        // Row 9: unprotected re-request after a comment. Same #41 shape with
        // reviewDecision=null. Re-request wins → "Waiting for review".
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil,
            reviewRequestCount: 1,
            latestReviewVerdict: .commented,
            reReviewRequested: true
        ) == .waitingForReview)

        // Row 10: #50 — unprotected approved PR with a new (different)
        // reviewer added. reReviewRequested=false so the .approved verdict
        // wins rather than masking it as "Waiting".
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil,
            reviewRequestCount: 1,
            latestReviewVerdict: .approved,
            reReviewRequested: false
        ) == .approved)

        // Compound: Steven commented and was re-requested while Alex is also
        // pending (so reviewRequestCount=2). The re-request keeps us waiting
        // and suppresses the stale commented verdict — the re-request branch
        // beats the commented surfacing branch.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: .reviewRequired,
            reviewRequestCount: 2,
            latestReviewVerdict: .commented,
            reReviewRequested: true
        ) == .waitingForReview)

        // Row 11: unprotected comment back with another reviewer pending.
        // reReviewRequested=false → "Commented" surfaces just like row 2.
        #expect(PullRequest.deriveAuthoredStatus(
            reviewDecision: nil,
            reviewRequestCount: 1,
            latestReviewVerdict: .commented,
            reReviewRequested: false
        ) == .commented)
    }

    @Test("deriveReReviewRequested cross-references pending and reviewed logins")
    func reReviewRequestedDerivation() {
        // Empty pending list → false (no one to match).
        #expect(PullRequest.deriveReReviewRequested(
            pendingReviewerLogins: [],
            reviewedByLogins: ["alex"]
        ) == false)
        // Empty reviewed list → false (no prior reviews to match against).
        #expect(PullRequest.deriveReReviewRequested(
            pendingReviewerLogins: ["alex"],
            reviewedByLogins: []
        ) == false)
        // Disjoint logins → false (brand-new reviewer added).
        #expect(PullRequest.deriveReReviewRequested(
            pendingReviewerLogins: ["alex"],
            reviewedByLogins: ["steven"]
        ) == false)
        // Overlapping login → true (re-request of someone who reviewed).
        #expect(PullRequest.deriveReReviewRequested(
            pendingReviewerLogins: ["alex", "priya"],
            reviewedByLogins: ["steven", "alex"]
        ) == true)
        // Case-insensitive match → true (GitHub logins are case-insensitive).
        #expect(PullRequest.deriveReReviewRequested(
            pendingReviewerLogins: ["Alex"],
            reviewedByLogins: ["alex"]
        ) == true)
    }

    @Test("Review verdict ranks changes-requested over approved over commented")
    func reviewVerdictDerivation() {
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: []) == nil)
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.commented]) == .commented)
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.approved]) == .approved)
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.changesRequested]) == .changesRequested)
        // CHANGES_REQUESTED from any reviewer blocks merge, even with approvals from others.
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.approved, .changesRequested]) == .changesRequested)
        // APPROVED still wins over COMMENTED.
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.commented, .approved]) == .approved)
        // Exhaustive precedence with all three opinionated cases present.
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.commented, .approved, .changesRequested]) == .changesRequested)
        // DISMISSED and PENDING are ignored.
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.dismissed]) == nil)
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.dismissed, .dismissed]) == nil)
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.dismissed, .pending]) == nil)
        #expect(PullRequest.deriveReviewVerdict(latestReviewStates: [.dismissed, .approved]) == .approved)
    }

    @Test("PRReviewState raw values match GitHub PullRequestReviewState enum")
    func reviewStateRawValues() {
        #expect(PRReviewState.approved.rawValue == "APPROVED")
        #expect(PRReviewState.changesRequested.rawValue == "CHANGES_REQUESTED")
        #expect(PRReviewState.commented.rawValue == "COMMENTED")
        #expect(PRReviewState.dismissed.rawValue == "DISMISSED")
        #expect(PRReviewState.pending.rawValue == "PENDING")
    }

    @Test("PRReviewDecision raw values match GitHub PullRequestReviewDecision enum")
    func reviewDecisionRawValues() {
        #expect(PRReviewDecision.approved.rawValue == "APPROVED")
        #expect(PRReviewDecision.changesRequested.rawValue == "CHANGES_REQUESTED")
        #expect(PRReviewDecision.reviewRequired.rawValue == "REVIEW_REQUIRED")
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

@Suite("Inbox window height")
struct InboxWindowHeightTests {

    @Test("Empty snapshot stays at or above the minimum floor")
    func emptySnapshotClampsToFloor() {
        let height = InboxWindowHeight.compute(
            authoredPRCount: 0,
            reviewRequestedPRCount: 0,
            assignedIssueCount: 0,
            screenVisibleHeight: 1000
        )
        // Each empty section still renders one "No ..." row, so the
        // computed height sits just above the 320 floor. The clamp
        // guarantees we never drop below it.
        #expect(height >= InboxWindowHeight.minimumHeight)
        // And the cap is far away, so the floor is the only thing
        // keeping us honest here.
        let cap = 1000 * InboxWindowHeight.screenFraction
        #expect(height < cap)
    }

    @Test("Small snapshot lands between floor and screen cap")
    func smallSnapshotBelowScreenCap() {
        let screen: CGFloat = 1000
        let height = InboxWindowHeight.compute(
            authoredPRCount: 2,
            reviewRequestedPRCount: 1,
            assignedIssueCount: 0,
            screenVisibleHeight: screen
        )
        let cap = screen * InboxWindowHeight.screenFraction
        #expect(height >= InboxWindowHeight.minimumHeight)
        #expect(height <= cap)
    }

    @Test("Huge snapshot is clamped to 80% of screen height")
    func hugeSnapshotClampsToScreenCap() {
        let screen: CGFloat = 1000
        let height = InboxWindowHeight.compute(
            authoredPRCount: 50,
            reviewRequestedPRCount: 50,
            assignedIssueCount: 50,
            screenVisibleHeight: screen
        )
        #expect(height == screen * InboxWindowHeight.screenFraction)
    }

    @Test("Default screen height parameter is deterministic")
    func defaultScreenHeightIsDeterministic() {
        // Callers without an NSScreen (and tests) should get a stable
        // ceiling derived from the documented fallback, not the host's
        // physical display.
        let height = InboxWindowHeight.compute(
            authoredPRCount: 100,
            reviewRequestedPRCount: 100,
            assignedIssueCount: 100
        )
        let expectedCap =
            InboxWindowHeight.fallbackScreenHeight
            * InboxWindowHeight.screenFraction
        #expect(height == expectedCap)
    }
}

@Suite("Window resize clamp")
struct WindowResizeClampTests {

    // A typical screen: 1440x900 with the menu bar excluded.
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test("Target fits within the screen — frame uses the full target height")
    func targetFitsUnclamped() {
        // Window top at y=800, target height 400 — bottom lands at 400,
        // safely above visibleFrame.minY (0).
        let current = CGRect(x: 100, y: 600, width: 720, height: 200)
        let clamped = WindowResizeClamp.clampedFrame(
            currentFrame: current,
            targetFrameHeight: 400,
            visibleFrame: visibleFrame
        )
        #expect(clamped.height == 400)
        // Anchored to the current top edge.
        #expect(clamped.maxY == current.maxY)
    }

    @Test("Target overflows below — height shrinks so the bottom stays on screen")
    func clampsHeightWhenWindowSitsLow() {
        // Window top at y=300, only 300pt of vertical room down to the
        // bottom of the visible frame. Asking for 600 should clamp to 300.
        let current = CGRect(x: 100, y: 100, width: 720, height: 200)
        let clamped = WindowResizeClamp.clampedFrame(
            currentFrame: current,
            targetFrameHeight: 600,
            visibleFrame: visibleFrame
        )
        #expect(clamped.height == 300)
        #expect(clamped.minY == visibleFrame.minY)
        #expect(clamped.maxY == current.maxY)
    }

    @Test("Top above the screen is pulled back to the visible top edge")
    func clampsTopWhenWindowSitsHigh() {
        // Pathological remembered frame: top above the visible area.
        let current = CGRect(x: 100, y: 800, width: 720, height: 200)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let clamped = WindowResizeClamp.clampedFrame(
            currentFrame: current,
            targetFrameHeight: 400,
            visibleFrame: visible
        )
        #expect(clamped.maxY == visible.maxY)
        #expect(clamped.height == 400)
    }

    @Test("Empty visible frame is a no-op")
    func emptyVisibleFrameIsNoOp() {
        let current = CGRect(x: 100, y: 100, width: 720, height: 200)
        let clamped = WindowResizeClamp.clampedFrame(
            currentFrame: current,
            targetFrameHeight: 600,
            visibleFrame: .zero
        )
        #expect(clamped == current)
    }
}

@Suite("App model lifecycle")
@MainActor
struct AppModelLifecycleTests {

    @Test("First-sync flag starts false at init")
    func firstSyncFlagDefaultsFalse() {
        let model = AppModel()
        #expect(model.hasCompletedFirstSync == false)
        #expect(model.snapshot == nil)
        #expect(model.lastError == nil)
    }
}

@Suite("UI font scale")
struct UIFontScaleTests {

    @Test("Actual size is one and lives in the documented range")
    func actualSizeIsCanonical() {
        #expect(UIFontScale.actualSize == 1.0)
        #expect(UIFontScale.minimum < UIFontScale.actualSize)
        #expect(UIFontScale.actualSize < UIFontScale.maximum)
    }

    @Test("Zoom in adds one step from canonical points")
    func zoomInStepsForward() {
        #expect(approximately(UIFontScale.zoomIn(1.0), 1.1))
        #expect(approximately(UIFontScale.zoomIn(0.7), 0.8))
        #expect(approximately(UIFontScale.zoomIn(1.2), 1.3))
    }

    @Test("Zoom out subtracts one step from canonical points")
    func zoomOutStepsBackward() {
        #expect(approximately(UIFontScale.zoomOut(1.0), 0.9))
        #expect(approximately(UIFontScale.zoomOut(1.6), 1.5))
        #expect(approximately(UIFontScale.zoomOut(0.8), 0.7))
    }

    @Test("Zoom in clamps at the documented maximum")
    func zoomInClampsAtMaximum() {
        #expect(approximately(UIFontScale.zoomIn(UIFontScale.maximum), UIFontScale.maximum))
        // One step above the cap also stays clamped.
        #expect(approximately(UIFontScale.zoomIn(UIFontScale.maximum + 0.5), UIFontScale.maximum))
    }

    @Test("Zoom out clamps at the documented minimum")
    func zoomOutClampsAtMinimum() {
        #expect(approximately(UIFontScale.zoomOut(UIFontScale.minimum), UIFontScale.minimum))
        // One step below the floor also stays clamped.
        #expect(approximately(UIFontScale.zoomOut(UIFontScale.minimum - 0.5), UIFontScale.minimum))
    }

    @Test("Successive zoom-ins walk cleanly from minimum to maximum")
    func successiveZoomInsHitMaximum() {
        var scale = UIFontScale.minimum
        // Ten steps of 0.1 take us from 0.7 to 1.6 inclusive (9 jumps + 1 extra clamp).
        for _ in 0..<20 {
            scale = UIFontScale.zoomIn(scale)
        }
        #expect(approximately(scale, UIFontScale.maximum))
    }

    @Test("Successive zoom-outs walk cleanly from maximum to minimum")
    func successiveZoomOutsHitMinimum() {
        var scale = UIFontScale.maximum
        for _ in 0..<20 {
            scale = UIFontScale.zoomOut(scale)
        }
        #expect(approximately(scale, UIFontScale.minimum))
    }

    @Test("Clamp snaps off-grid values to the nearest step")
    func clampSnapsToStepGrid() {
        // 1.03 rounds down to 1.0; 1.07 rounds up to 1.1.
        #expect(approximately(UIFontScale.clamp(1.03), 1.0))
        #expect(approximately(UIFontScale.clamp(1.07), 1.1))
        // Off-grid values outside the range still clamp into [min, max].
        #expect(approximately(UIFontScale.clamp(5.0), UIFontScale.maximum))
        #expect(approximately(UIFontScale.clamp(0.1), UIFontScale.minimum))
    }

    @Test("isAtMaximum / isAtMinimum gate the menu commands")
    func boundsReportingMatchesClamp() {
        #expect(UIFontScale.isAtMaximum(UIFontScale.maximum))
        #expect(UIFontScale.isAtMaximum(UIFontScale.maximum + 0.5))
        #expect(!UIFontScale.isAtMaximum(UIFontScale.actualSize))

        #expect(UIFontScale.isAtMinimum(UIFontScale.minimum))
        #expect(UIFontScale.isAtMinimum(UIFontScale.minimum - 0.5))
        #expect(!UIFontScale.isAtMinimum(UIFontScale.actualSize))
    }

    @Test("Non-finite scale values fall back to actual size")
    func clampSanitizesNonFiniteValues() {
        #expect(approximately(UIFontScale.clamp(.nan), UIFontScale.actualSize))
        #expect(approximately(UIFontScale.clamp(.infinity), UIFontScale.actualSize))
        #expect(approximately(UIFontScale.clamp(-.infinity), UIFontScale.actualSize))
    }

    /// Floating-point comparison helper. The step grid is 0.1, so a
    /// tolerance of 1e-9 catches arithmetic drift without false positives.
    private func approximately(
        _ lhs: CGFloat,
        _ rhs: CGFloat,
        tolerance: CGFloat = 1e-9
    ) -> Bool {
        abs(lhs - rhs) < tolerance
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
