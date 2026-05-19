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
    static let inbox = """
    query Inbox($authored: String!, $reviewReq: String!, $issues: String!) {
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
      reviewRequests(first: 1) { totalCount }
      latestReviews(first: 50) { nodes { state } }
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
