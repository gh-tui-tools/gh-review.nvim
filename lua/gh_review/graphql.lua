-- GraphQL queries and mutations for PR review.

local M = {}

M.QUERY_PR_DETAILS = [[
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        id
        number
        title
        state
        baseRefName
        baseRefOid
        headRefName
        headRefOid
        headRepository {
          owner { login }
          name
        }
        files(first: 100) {
          nodes {
            path
            additions
            deletions
            changeType
          }
        }
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            isOutdated
            line
            originalLine
            startLine
            originalStartLine
            diffSide
            path
            comments(first: 50) {
              nodes {
                id
                body
                author {
                  login
                }
                createdAt
                pullRequestReview {
                  id
                  state
                }
              }
            }
          }
        }
        reviews(first: 10, states: PENDING) {
          nodes {
            id
            state
          }
        }
      }
    }
  }
]]

M.QUERY_REVIEW_THREADS = [[
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            isOutdated
            line
            originalLine
            startLine
            originalStartLine
            diffSide
            path
            comments(first: 50) {
              nodes {
                id
                body
                author {
                  login
                }
                createdAt
                pullRequestReview {
                  id
                  state
                }
              }
            }
          }
        }
      }
    }
  }
]]

M.MUTATION_START_REVIEW = [[
  mutation($pullRequestId: ID!) {
    addPullRequestReview(input: {pullRequestId: $pullRequestId}) {
      pullRequestReview {
        id
        state
      }
    }
  }
]]

M.MUTATION_CREATE_AND_SUBMIT_REVIEW = [[
  mutation($pullRequestId: ID!, $event: PullRequestReviewEvent!, $body: String) {
    addPullRequestReview(input: {pullRequestId: $pullRequestId, event: $event, body: $body}) {
      pullRequestReview {
        id
        state
      }
    }
  }
]]

M.MUTATION_SUBMIT_REVIEW = [[
  mutation($reviewId: ID!, $event: PullRequestReviewEvent!, $body: String) {
    submitPullRequestReview(input: {pullRequestReviewId: $reviewId, event: $event, body: $body}) {
      pullRequestReview {
        id
        state
      }
    }
  }
]]

M.MUTATION_ADD_REVIEW_THREAD = [[
  mutation($pullRequestId: ID!, $body: String!, $path: String!, $line: Int!, $side: DiffSide!, $startLine: Int, $startSide: DiffSide, $pullRequestReviewId: ID) {
    addPullRequestReviewThread(input: {
      pullRequestId: $pullRequestId,
      body: $body,
      path: $path,
      line: $line,
      side: $side,
      startLine: $startLine,
      startSide: $startSide,
      pullRequestReviewId: $pullRequestReviewId
    }) {
      thread {
        id
        isResolved
        line
        startLine
        diffSide
        path
        comments(first: 50) {
          nodes {
            id
            body
            author {
              login
            }
            createdAt
          }
        }
      }
    }
  }
]]

M.MUTATION_ADD_REVIEW_COMMENT = [[
  mutation($pullRequestReviewId: ID!, $threadId: ID!, $body: String!) {
    addPullRequestReviewComment(input: {
      pullRequestReviewId: $pullRequestReviewId,
      inReplyTo: $threadId,
      body: $body
    }) {
      comment {
        id
        body
        author {
          login
        }
        createdAt
      }
    }
  }
]]

M.MUTATION_RESOLVE_THREAD = [[
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread {
        id
        isResolved
      }
    }
  }
]]

M.MUTATION_UNRESOLVE_THREAD = [[
  mutation($threadId: ID!) {
    unresolveReviewThread(input: {threadId: $threadId}) {
      thread {
        id
        isResolved
      }
    }
  }
]]

M.MUTATION_DELETE_REVIEW = [[
  mutation($pullRequestReviewId: ID!) {
    deletePullRequestReview(input: {pullRequestReviewId: $pullRequestReviewId}) {
      pullRequestReview {
        id
        state
      }
    }
  }
]]

return M
