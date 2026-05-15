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
            author { login }
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
      author { login }
      repository { nameWithOwner }
      reviewDecision
      reviews(first: 1) { totalCount }
    }
    """
}
