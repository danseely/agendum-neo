import CoreGraphics

/// Pure computation for the inbox window's ideal content height.
///
/// Extracted from `RootView` so it can be unit-tested without standing up
/// a SwiftUI view or an `NSScreen`. The view passes row counts from the
/// current snapshot and the screen's visible height; the function returns
/// a clamped height for `idealHeight` on the window's content frame.
enum InboxWindowHeight {
    /// Minimum floor for the window's ideal height. Matches the `minHeight`
    /// applied on `RootView` so the loading screen and tiny snapshots
    /// don't collapse the window.
    static let minimumHeight: CGFloat = 320

    /// Fraction of the screen's visible height we'll grow to before clamping.
    static let screenFraction: CGFloat = 0.8

    /// Fallback screen height when no `NSScreen` is available.
    static let fallbackScreenHeight: CGFloat = 800

    // Estimated row metrics. These are deliberate over-estimates so we
    // don't clip rows; if too tall, the user can shrink the window.
    static let rowHeight: CGFloat = 30
    static let sectionHeaderHeight: CGFloat = 34
    static let sectionSpacing: CGFloat = 12
    static let toolbarPadding: CGFloat = 52
    static let footerPadding: CGFloat = 40
    static let listVerticalPadding: CGFloat = 16

    /// Compute the ideal window content height for a snapshot.
    ///
    /// - Parameters:
    ///   - authoredPRCount: number of rows in the "Your PRs" section.
    ///   - reviewRequestedPRCount: number of rows in the "Awaiting your review" section.
    ///   - assignedIssueCount: number of rows in the "Assigned issues" section.
    ///   - screenVisibleHeight: the host screen's visible-frame height. Defaults
    ///     to `fallbackScreenHeight` so callers without an `NSScreen` (and tests)
    ///     get a deterministic cap.
    /// - Returns: a value in `[minimumHeight, screenVisibleHeight * screenFraction]`.
    static func compute(
        authoredPRCount: Int,
        reviewRequestedPRCount: Int,
        assignedIssueCount: Int,
        screenVisibleHeight: CGFloat = fallbackScreenHeight
    ) -> CGFloat {
        // Each section renders at least one row ("No PRs"/"No issues")
        // when its body is empty, so floor each section count at 1.
        let totalRows =
            max(authoredPRCount, 1)
            + max(reviewRequestedPRCount, 1)
            + max(assignedIssueCount, 1)

        let contentHeight =
            CGFloat(totalRows) * rowHeight
            + 3 * sectionHeaderHeight
            + 2 * sectionSpacing
            + listVerticalPadding
            + toolbarPadding
            + footerPadding

        let cap = screenVisibleHeight * screenFraction
        return min(max(contentHeight, minimumHeight), cap)
    }
}
