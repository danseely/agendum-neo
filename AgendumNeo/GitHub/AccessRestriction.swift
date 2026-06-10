import Foundation

/// A non-fatal access restriction detected on a GitHub response. The canonical
/// signal is the `X-GitHub-SSO` response header: when the `gh`-issued token
/// isn't authorized for an organization that enforces SAML single sign-on,
/// GitHub does NOT error — `viewer.organizations` still lists the org (so it
/// shows in the namespace picker), but `search` over that org's repos silently
/// drops the results and the response carries an `X-GitHub-SSO` header. Without
/// detecting this the inbox just looks empty, which reads as a bug. See the
/// "only works for me" investigation: a returning user has an authorized token,
/// a new user in an SSO org sees a blank inbox.
///
/// Header forms (per GitHub docs):
///   X-GitHub-SSO: partial-results; organizations=ORG_ID,ORG_ID
///   X-GitHub-SSO: required; url=https://github.com/orgs/ORG/sso?authorization_request=ID
enum AccessRestriction: Sendable, Equatable {
    /// Some results were omitted because the token isn't SSO-authorized for one
    /// or more orgs touched by the query. This is what a scoped `user:<org>`
    /// search returns when that org enforces SSO.
    case ssoPartialResults
    /// The request was blocked pending SSO authorization. Carries the
    /// authorization URL when GitHub provides one.
    case ssoRequired(url: URL?)

    /// Parse the value of an `X-GitHub-SSO` response header. Returns nil for the
    /// common unrestricted case (header absent or empty).
    static func parse(ssoHeader raw: String?) -> AccessRestriction? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        let directive = raw
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        switch directive {
        case "required":
            return .ssoRequired(url: extractURL(from: raw))
        case "partial-results":
            return .ssoPartialResults
        default:
            // An unrecognized future directive still means access is being
            // restricted — surface it rather than rendering a blank inbox.
            return .ssoPartialResults
        }
    }

    /// The org-authorization URL, when GitHub supplied one (`required` form).
    var authorizationURL: URL? {
        if case let .ssoRequired(url) = self { return url }
        return nil
    }

    private static func extractURL(from raw: String) -> URL? {
        for segment in raw.split(separator: ";") {
            let part = segment.trimmingCharacters(in: .whitespaces)
            if part.lowercased().hasPrefix("url=") {
                return URL(string: String(part.dropFirst("url=".count)))
            }
        }
        return nil
    }

    // MARK: - User-facing copy
    //
    // A scoped inbox query only ever references the selected namespace owner, so
    // any SSO restriction observed during the fetch pertains to that owner —
    // safe to name it directly. Plain ASCII, no em-dashes, matching the rest of
    // the app's UI strings.

    func title(owner: String) -> String {
        "Can't load \(owner)'s pull requests"
    }

    func detail(owner: String) -> String {
        switch self {
        case .ssoRequired:
            return "Your GitHub CLI token isn't authorized for \(owner)'s SAML single sign-on, so its pull requests and issues are hidden. Authorize the token for \(owner), then refresh."
        case .ssoPartialResults:
            return "Your GitHub CLI token isn't authorized for \(owner)'s SAML single sign-on, so its pull requests and issues are hidden. Authorize the token under GitHub Settings > Applications (or run `gh auth login` again and complete the SSO prompt), then refresh."
        }
    }

    /// One-line form for the banner shown above a partially-restricted list.
    func bannerText(owner: String) -> String {
        "Some \(owner) results may be hidden. Your GitHub CLI token isn't authorized for its SAML single sign-on."
    }
}
