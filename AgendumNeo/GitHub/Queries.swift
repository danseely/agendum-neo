import Foundation

enum Queries {
    static let namespaces = """
    query Namespaces {
      viewer {
        login
        organizations(first: 100) {
          nodes { login }
        }
      }
    }
    """

    // `latestReviews(first: 50)` returns the latest review per reviewer
    // (server-side dedup; PENDING reviews are excluded). 50 is well above
    // any realistic human-reviewer count on a single PR. Repos with large
    // CODEOWNERS bot fleets could in theory exceed this and silently drop
    // a CHANGES_REQUESTED from a truncated reviewer; bump the cap if that
    // ever happens in practice.
    //
    // `reviewRequests(first: 50)` is fetched with reviewer logins (not just
    // a `totalCount`) so we can cross-reference against `latestReviews` to
    // tell a re-request (same person who already reviewed, issue #41) from
    // a brand-new reviewer added after a verdict came back (issue #50 and
    // the Alex+Steven masking case). `totalCount` is preserved so
    // `reviewRequestCount` stays accurate even if `nodes` truncates. Same
    // 50-cap truncation caveat applies as with `latestReviews`.
    //
    // Note: `... on User { login }` is deliberately the only specialization
    // on `requestedReviewer`. Team / Bot / Mannequin reviewers are
    // intentionally not matched here — they can never collide with a
    // `latestReviews` author login, so they fall through as "new pending"
    // rather than re-requests (issue #50). Don't add `... on Team { slug }`
    // or similar expecting it to count as a re-request without revisiting
    // `deriveReReviewRequested`.
    // `orgAccessProbe` is a zero-extra-request SSO probe folded into the inbox
    // query. A scoped `search(user:<org>)` against a fully SSO-locked org can
    // come back as 200 with empty `nodes` and NO `errors`/header — search has
    // nothing accessible to traverse, so it looks identical to a genuinely
    // empty inbox. Direct node access does NOT: `organization(login:)` returns
    // a FORBIDDEN / `saml_failure` error for an org the token isn't SSO-authorized
    // for. Including it here lets `fetchInbox` distinguish "blocked by SSO" from
    // "nothing assigned" in the same round-trip. It's `@include`-gated to org
    // namespaces only — for a personal `.user` namespace `organization(login:)`
    // would 404 (NOT_FOUND), which we must not treat as an error.
    static let inbox = """
    query Inbox($authored: String!, $reviewReq: String!, $issues: String!, $owner: String!, $includeOrgProbe: Boolean!) {
      orgAccessProbe: organization(login: $owner) @include(if: $includeOrgProbe) {
        login
      }
      authored: search(query: $authored, type: ISSUE, first: 50) {
        nodes { ...prFields }
      }
      reviewRequested: search(query: $reviewReq, type: ISSUE, first: 50) {
        nodes { ...prFields }
      }
      assignedIssues: search(query: $issues, type: ISSUE, first: 50) {
        nodes {
          __typename
          ... on Issue {
            id
            number
            title
            url
            updatedAt
            author { ...authorFields }
            repository { nameWithOwner }
          }
        }
      }
    }

    fragment prFields on PullRequest {
      __typename
      id
      number
      title
      url
      updatedAt
      isDraft
      author { ...authorFields }
      repository { nameWithOwner }
      reviewRequests(first: 50) {
        totalCount
        nodes {
          requestedReviewer {
            __typename
            ... on User { login }
          }
        }
      }
      latestReviews(first: 50) {
        nodes {
          state
          author { login }
        }
      }
      reviewDecision
    }

    fragment authorFields on Actor {
      login
      ... on User {
        name
      }
    }
    """
}
