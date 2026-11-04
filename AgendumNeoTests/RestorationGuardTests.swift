import Testing
import Foundation
@testable import AgendumNeo

@Suite("RestorationGuard")
struct RestorationGuardTests {

    @Test("First launch with no stamp declines restoration")
    func firstLaunch() {
        #expect(RestorationGuard.shouldDecline(storedOSMajor: nil, currentOSMajor: 27, lastLaunchDied: false))
    }

    @Test("OS major version change declines restoration")
    func osChanged() {
        #expect(RestorationGuard.shouldDecline(storedOSMajor: 26, currentOSMajor: 27, lastLaunchDied: false))
    }

    @Test("A launch that died during restoration declines the next one")
    func lastLaunchDied() {
        #expect(RestorationGuard.shouldDecline(storedOSMajor: 27, currentOSMajor: 27, lastLaunchDied: true))
    }

    @Test("Same OS and a clean last launch restores normally")
    func normalLaunch() {
        #expect(!RestorationGuard.shouldDecline(storedOSMajor: 27, currentOSMajor: 27, lastLaunchDied: false))
    }
}

@Suite("RestorationLaunchLedger")
struct RestorationLaunchLedgerTests {

    /// Runs `body` against a fresh defaults suite and removes it afterwards.
    private func withLedger(suffix: String = "", _ body: (RestorationLaunchLedger, UserDefaults) -> Void) {
        let suiteName = "RestorationLaunchLedgerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(RestorationLaunchLedger(defaults: defaults, keySuffix: suffix), defaults)
    }

    @Test("First launch declines, the next clean launch restores")
    func firstLaunchThenClean() {
        withLedger { ledger, _ in
            #expect(ledger.beginLaunch(osMajor: 27))
            ledger.restorationFinished()
            #expect(!ledger.beginLaunch(osMajor: 27))
        }
    }

    @Test("A launch that dies before restoring makes the next one decline, once")
    func diedDuringRestore() {
        withLedger { ledger, _ in
            _ = ledger.beginLaunch(osMajor: 27)
            ledger.restorationFinished()
            #expect(!ledger.beginLaunch(osMajor: 27))  // dies: restorationFinished never called
            #expect(ledger.beginLaunch(osMajor: 27))
            ledger.restorationFinished()
            #expect(!ledger.beginLaunch(osMajor: 27))
        }
    }

    @Test("An OS major version change declines exactly once")
    func osChangeOnce() {
        withLedger { ledger, _ in
            _ = ledger.beginLaunch(osMajor: 26)
            ledger.restorationFinished()
            #expect(!ledger.beginLaunch(osMajor: 26))
            ledger.restorationFinished()
            #expect(ledger.beginLaunch(osMajor: 27))
            ledger.restorationFinished()
            #expect(!ledger.beginLaunch(osMajor: 27))
        }
    }

    @Test("The marker is set for the whole launch and cleared when restoration finishes")
    func markerLifecycle() {
        withLedger { ledger, defaults in
            _ = ledger.beginLaunch(osMajor: 27)
            #expect(defaults.bool(forKey: ledger.launchMarkerKey))
            #expect(defaults.integer(forKey: ledger.osVersionKey) == 27)
            ledger.restorationFinished()
            #expect(!defaults.bool(forKey: ledger.launchMarkerKey))
        }
    }

    @Test("Debug and release bookkeeping don't affect each other")
    func flavorsAreSeparate() {
        withLedger(suffix: ".debug") { debug, defaults in
            let release = RestorationLaunchLedger(defaults: defaults, keySuffix: "")
            _ = debug.beginLaunch(osMajor: 27)
            debug.restorationFinished()
            #expect(release.beginLaunch(osMajor: 27))  // release record still gets its heal
            #expect(!debug.beginLaunch(osMajor: 27))
        }
    }
}
