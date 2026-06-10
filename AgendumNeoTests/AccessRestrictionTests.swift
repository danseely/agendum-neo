import Testing
import Foundation
@testable import AgendumNeo

@Suite("AccessRestriction")
struct AccessRestrictionTests {

    @Test("Absent or empty header is not a restriction")
    func absentHeader() {
        #expect(AccessRestriction.parse(ssoHeader: nil) == nil)
        #expect(AccessRestriction.parse(ssoHeader: "") == nil)
        #expect(AccessRestriction.parse(ssoHeader: "   ") == nil)
    }

    @Test("partial-results header parses to ssoPartialResults")
    func partialResults() {
        let r = AccessRestriction.parse(ssoHeader: "partial-results; organizations=12345,67890")
        #expect(r == .ssoPartialResults)
        #expect(r?.authorizationURL == nil)
    }

    @Test("required header parses with its authorization URL")
    func requiredWithURL() {
        let header = "required; url=https://github.com/orgs/acme/sso?authorization_request=ABC123"
        let r = AccessRestriction.parse(ssoHeader: header)
        #expect(r == .ssoRequired(url: URL(string: "https://github.com/orgs/acme/sso?authorization_request=ABC123")))
        #expect(r?.authorizationURL?.absoluteString == "https://github.com/orgs/acme/sso?authorization_request=ABC123")
    }

    @Test("required header without a url still parses, URL nil")
    func requiredWithoutURL() {
        let r = AccessRestriction.parse(ssoHeader: "required")
        #expect(r == .ssoRequired(url: nil))
        #expect(r?.authorizationURL == nil)
    }

    @Test("Directive matching is case- and whitespace-insensitive")
    func looseDirective() {
        #expect(AccessRestriction.parse(ssoHeader: "  PARTIAL-RESULTS ; organizations=1") == .ssoPartialResults)
        #expect(AccessRestriction.parse(ssoHeader: "Required; URL=https://x.test/sso")
                == .ssoRequired(url: URL(string: "https://x.test/sso")))
    }

    @Test("Unknown future directive is treated as a restriction, not ignored")
    func unknownDirective() {
        #expect(AccessRestriction.parse(ssoHeader: "some-new-thing; foo=bar") == .ssoPartialResults)
    }

    @Test("User-facing copy names the owner")
    func copyNamesOwner() {
        let r = AccessRestriction.ssoPartialResults
        #expect(r.title(owner: "acme").contains("acme"))
        #expect(r.detail(owner: "acme").contains("acme"))
        #expect(r.bannerText(owner: "acme").contains("acme"))
    }
}
