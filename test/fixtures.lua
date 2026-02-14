-- Fixture data for gh-review.nvim tests.
-- Returns tables matching the GraphQL response shape.

local M = {}

-- Full PR data matching the structure of a QUERY_PR_DETAILS response.
function M.mock_pr_data()
  return {
    data = {
      repository = {
        pullRequest = {
          id = "PR_abc123",
          number = 42,
          title = "Add feature X",
          state = "OPEN",
          baseRefName = "main",
          baseRefOid = "aaa111",
          headRefName = "feature-x",
          headRefOid = "bbb222",
          headRepository = {
            owner = { login = "testowner" },
            name = "testrepo",
          },
          files = {
            nodes = {
              { path = "src/new_file.ts", additions = 50, deletions = 0, changeType = "ADDED" },
              { path = "src/existing.ts", additions = 10, deletions = 5, changeType = "MODIFIED" },
              { path = "src/old_file.ts", additions = 0, deletions = 30, changeType = "DELETED" },
            }
          },
          reviewThreads = {
            nodes = {
              {
                id = "thread_1",
                isResolved = false,
                isOutdated = false,
                line = 10,
                originalLine = 10,
                startLine = vim.NIL,
                originalStartLine = vim.NIL,
                diffSide = "RIGHT",
                path = "src/new_file.ts",
                comments = { nodes = {
                  { id = "comment_1", body = "Looks good", author = { login = "alice" }, createdAt = "2025-01-15T10:30:00Z", pullRequestReview = { id = "rev_1", state = "COMMENTED" } },
                } },
              },
              {
                id = "thread_2",
                isResolved = true,
                isOutdated = false,
                line = 25,
                originalLine = 25,
                startLine = 20,
                originalStartLine = 20,
                diffSide = "RIGHT",
                path = "src/new_file.ts",
                comments = { nodes = {
                  { id = "comment_2", body = "Fix this", author = { login = "bob" }, createdAt = "2025-01-15T11:00:00Z", pullRequestReview = { id = "rev_2", state = "COMMENTED" } },
                  { id = "comment_3", body = "Done", author = { login = "alice" }, createdAt = "2025-01-15T12:00:00Z", pullRequestReview = { id = "rev_2", state = "COMMENTED" } },
                } },
              },
              {
                id = "thread_3",
                isResolved = false,
                isOutdated = false,
                line = vim.NIL,
                originalLine = 8,
                startLine = vim.NIL,
                originalStartLine = vim.NIL,
                diffSide = "RIGHT",
                path = "src/existing.ts",
                comments = { nodes = {
                  { id = "comment_4", body = "General comment", author = { login = "bob" }, createdAt = "2025-01-15T13:00:00Z", pullRequestReview = { id = "rev_3", state = "COMMENTED" } },
                } },
              },
              {
                id = "thread_4",
                isResolved = false,
                isOutdated = false,
                line = 5,
                originalLine = 5,
                startLine = vim.NIL,
                originalStartLine = vim.NIL,
                diffSide = "LEFT",
                path = "src/existing.ts",
                comments = { nodes = {
                  { id = "comment_5", body = "Pending note", author = { login = "alice" }, createdAt = "2025-01-16T09:00:00Z", pullRequestReview = { id = "pending_rev_1", state = "PENDING" } },
                } },
              },
            }
          },
          reviews = {
            nodes = {
              { id = "pending_rev_1", state = "PENDING" },
            }
          },
        }
      }
    }
  }
end

-- Fork PR data: headRepository owner differs from the repo owner.
function M.mock_fork_pr_data()
  local data = M.mock_pr_data()
  data.data.repository.pullRequest.headRepository = {
    owner = { login = "forkuser" },
    name = "testrepo",
  }
  data.data.repository.pullRequest.headRefName = "fork-feature"
  return data
end

-- PR data where headRepository is null (deleted fork).
function M.mock_deleted_fork_pr_data()
  local data = M.mock_pr_data()
  data.data.repository.pullRequest.headRepository = vim.NIL
  return data
end

-- Just the thread nodes list (for set_threads).
function M.mock_thread_nodes()
  local data = M.mock_pr_data()
  return data.data.repository.pullRequest.reviewThreads.nodes
end

-- PR data with all five change types.
function M.mock_all_change_types_pr_data()
  local data = M.mock_pr_data()
  data.data.repository.pullRequest.files.nodes = {
    { path = "src/new_file.ts", additions = 50, deletions = 0, changeType = "ADDED" },
    { path = "src/existing.ts", additions = 10, deletions = 5, changeType = "MODIFIED" },
    { path = "src/old_file.ts", additions = 0, deletions = 30, changeType = "DELETED" },
    { path = "src/moved.ts", additions = 2, deletions = 1, changeType = "RENAMED" },
    { path = "src/cloned.ts", additions = 0, deletions = 0, changeType = "COPIED" },
  }
  return data
end

return M
