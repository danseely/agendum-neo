import CoreGraphics
import SwiftUI

/// Pure helpers for the UI's global font-scale multiplier.
///
/// Extracted from `AppModel` / `AgendumNeoApp` so the clamp and step
/// behavior can be unit-tested without standing up a SwiftUI scene.
/// The scale is a multiplier applied to the system font size at the
/// root view; 1.0 means "actual size", 1.6 the documented maximum,
/// and 0.7 the documented minimum.
enum UIFontScale {
    /// Smallest allowed scale. Anything tighter and the rows become unreadable.
    static let minimum: CGFloat = 0.7
    /// Largest allowed scale. Anything looser and rows start clipping in the menu bar.
    static let maximum: CGFloat = 1.6
    /// Increment applied per Zoom In / Zoom Out invocation.
    static let step: CGFloat = 0.1
    /// The "Actual Size" scale, used by the corresponding menu command.
    static let actualSize: CGFloat = 1.0

    /// `UserDefaults` key for the persisted scale.
    static let defaultsKey = "AgendumNeo.uiFontScale"

    /// Clamp a raw scale value into `[minimum, maximum]` and round to the
    /// nearest `step` so successive zooms land on clean boundaries.
    /// Non-finite inputs (NaN / ±infinity) fall back to `actualSize`.
    static func clamp(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return actualSize }
        let bounded = min(max(value, minimum), maximum)
        let rounded = (bounded / step).rounded() * step
        // Re-clamp in case rounding nudged us back outside the range.
        return min(max(rounded, minimum), maximum)
    }

    /// Zoom in from the current scale, capped at `maximum`.
    static func zoomIn(_ current: CGFloat) -> CGFloat {
        clamp(current + step)
    }

    /// Zoom out from the current scale, floored at `minimum`.
    static func zoomOut(_ current: CGFloat) -> CGFloat {
        clamp(current - step)
    }

    /// `true` when another Zoom In would have no effect.
    static func isAtMaximum(_ current: CGFloat) -> Bool {
        clamp(current) >= maximum - (step / 2)
    }

    /// `true` when another Zoom Out would have no effect.
    static func isAtMinimum(_ current: CGFloat) -> Bool {
        clamp(current) <= minimum + (step / 2)
    }
}

private struct UIFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = UIFontScale.actualSize
}

extension EnvironmentValues {
    /// Global UI font-scale multiplier propagated from `AgendumNeoApp` to
    /// every view via `.environment(\.uiFontScale, …)`.
    var uiFontScale: CGFloat {
        get { self[UIFontScaleKey.self] }
        set { self[UIFontScaleKey.self] = newValue }
    }
}
