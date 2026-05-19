import CoreGraphics

/// Pure frame math for the post-launch window resize. Extracted from
/// `RootView` so the clamping logic can be unit-tested without standing up
/// an `NSWindow` or an `NSScreen`.
///
/// The window is anchored to its current top edge — so the title bar stays
/// put as the content grows — but if growing to `targetFrameHeight` would
/// push the bottom past the screen's visible frame, the height is reduced
/// so the bottom rests on `visibleFrame.minY` instead of falling off-screen.
enum WindowResizeClamp {
    static func clampedFrame(
        currentFrame: CGRect,
        targetFrameHeight: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        guard visibleFrame.height > 0, targetFrameHeight > 0 else {
            return currentFrame
        }

        // Anchor: keep the window's top edge where it is, but never above the
        // screen's visible top (defensive — handles a stale frame that's
        // already partly off-screen).
        let anchoredTop = min(currentFrame.maxY, visibleFrame.maxY)

        // How tall the window can be before its bottom falls below the
        // screen's visible bottom edge.
        let maxFittingHeight = max(0, anchoredTop - visibleFrame.minY)
        let height = min(targetFrameHeight, maxFittingHeight)

        var frame = currentFrame
        frame.size.height = height
        frame.origin.y = anchoredTop - height
        return frame
    }
}
