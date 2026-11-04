import AppKit
import ObjectiveC

/// Keeps a bad window-restoration record from crash-looping the app.
///
/// macOS 27's SwiftUI calls `fatalError` in `AppWindowsController.restoreWindow`
/// when AppKit hands it a record written by an older SwiftUI (#78). A trap can't
/// be caught, so the decision is made before AppKit restores anything: if the OS
/// major version changed since the last launch, or the previous launch died
/// before restoration finished, this launch declines every window restore.
/// AppKit then finishes restoring with no windows and writes fresh state, which
/// replaces the bad record. (`ApplePersistenceIgnoreState` skips the record but
/// never replaces it, so it can't heal.)
///
/// Declining is the documented contract of
/// `-[NSApplication restoreWindowWithIdentifier:state:completionHandler:]`:
/// return true and call the handler with a nil window. SwiftUI installs its own
/// `NSApplication` subclass and ignores `NSPrincipalClass`, so the method is
/// replaced at runtime instead of overridden, and only on launches that decline.
@MainActor
enum RestorationGuard {
    // Debug and release builds share this defaults domain, but AppKit keeps a
    // separate saved-state record per code-signing identity, so each build
    // flavor tracks its own stamp and marker.
    #if DEBUG
    private static let keySuffix = ".debug"
    #else
    private static let keySuffix = ""
    #endif
    private static let osVersionKey = "AgendumNeo.restorationOSMajorVersion" + keySuffix
    private static let launchMarkerKey = "AgendumNeo.restorationInProgress" + keySuffix

    /// Call from `App.init`, which runs before AppKit reads saved state.
    static func install() {
        // Unit tests run hosted in the app; leave NSApplication alone there.
        guard NSClassFromString("XCTestCase") == nil else { return }

        let defaults = UserDefaults.standard
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let decline = shouldDecline(
            storedOSMajor: defaults.object(forKey: osVersionKey) as? Int,
            currentOSMajor: major,
            lastLaunchDied: defaults.bool(forKey: launchMarkerKey)
        )

        defaults.set(major, forKey: osVersionKey)
        defaults.set(true, forKey: launchMarkerKey)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishRestoringWindowsNotification,
            object: nil,
            queue: .main
        ) { _ in
            UserDefaults.standard.set(false, forKey: launchMarkerKey)
        }

        if decline {
            declineWindowRestorationThisLaunch()
            openMainWindowAfterLaunchIfNeeded()
        }
    }

    /// Decline when the OS major version differs from the last launch (including
    /// a first launch with no stamp), or when the last launch never finished
    /// restoring windows.
    nonisolated static func shouldDecline(storedOSMajor: Int?, currentOSMajor: Int, lastLaunchDied: Bool) -> Bool {
        storedOSMajor != currentOSMajor || lastLaunchDied
    }

    /// After a declined restore SwiftUI treats the launch as restored and skips
    /// its default window, leaving only the menu bar extra. Once launch
    /// finishes, ask SwiftUI's app delegate for one through
    /// `applicationOpenUntitledFile(_:)`, which opens the `WindowGroup` window.
    private static func openMainWindowAfterLaunchIfNeeded() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let app = NSApplication.shared
                guard !app.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
                _ = app.delegate?.applicationOpenUntitledFile?(app)
            }
        }
    }

    private static func declineWindowRestorationThisLaunch() {
        typealias Completion = @convention(block) (NSWindow?, NSError?) -> Void
        let selector = #selector(NSApplication.restoreWindow(withIdentifier:state:completionHandler:))
        guard let method = class_getInstanceMethod(NSApplication.self, selector) else { return }
        let decline: @convention(block) (NSApplication, NSString, NSCoder, Completion) -> Bool = { _, _, _, completion in
            completion(nil, nil)
            return true
        }
        method_setImplementation(method, imp_implementationWithBlock(decline))
    }
}
