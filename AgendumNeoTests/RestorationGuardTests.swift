import Testing
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
