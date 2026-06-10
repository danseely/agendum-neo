import Testing
import Foundation
@testable import AgendumNeo

@Suite("RootView.shouldShowRestriction")
struct RootViewRestrictionTests {

    @Test("Org namespace, empty inbox, with restriction -> fullScreen")
    func orgEmptyRestriction() {
        let display = RootView.shouldShowRestriction(
            kind: .org,
            restriction: .ssoRequired(url: URL(string: "https://github.com/orgs/acme/sso")),
            inboxEmpty: true
        )
        #expect(display == .fullScreen)
    }

    @Test("Org namespace, non-empty inbox, with restriction -> banner")
    func orgNonEmptyRestriction() {
        let display = RootView.shouldShowRestriction(
            kind: .org,
            restriction: .ssoPartialResults,
            inboxEmpty: false
        )
        #expect(display == .banner)
    }

    @Test("User namespace, empty inbox, with restriction -> none")
    func userEmptyRestriction() {
        let display = RootView.shouldShowRestriction(
            kind: .user,
            restriction: .ssoRequired(url: nil),
            inboxEmpty: true
        )
        #expect(display == .none)
    }

    @Test("Nil restriction -> none regardless of namespace/emptiness")
    func nilRestriction() {
        #expect(RootView.shouldShowRestriction(kind: .org, restriction: nil, inboxEmpty: true) == .none)
        #expect(RootView.shouldShowRestriction(kind: .org, restriction: nil, inboxEmpty: false) == .none)
        #expect(RootView.shouldShowRestriction(kind: .user, restriction: nil, inboxEmpty: true) == .none)
        #expect(RootView.shouldShowRestriction(kind: nil, restriction: nil, inboxEmpty: true) == .none)
    }
}
