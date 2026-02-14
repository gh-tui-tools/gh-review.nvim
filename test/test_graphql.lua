-- Tests for lua/gh_review/graphql.lua

local h = require("test.helpers")
local graphql = require("gh_review.graphql")

local constants = {
  { name = "QUERY_PR_DETAILS", val = graphql.QUERY_PR_DETAILS },
  { name = "QUERY_REVIEW_THREADS", val = graphql.QUERY_REVIEW_THREADS },
  { name = "MUTATION_START_REVIEW", val = graphql.MUTATION_START_REVIEW },
  { name = "MUTATION_SUBMIT_REVIEW", val = graphql.MUTATION_SUBMIT_REVIEW },
  { name = "MUTATION_ADD_REVIEW_THREAD", val = graphql.MUTATION_ADD_REVIEW_THREAD },
  { name = "MUTATION_ADD_REVIEW_COMMENT", val = graphql.MUTATION_ADD_REVIEW_COMMENT },
  { name = "MUTATION_RESOLVE_THREAD", val = graphql.MUTATION_RESOLVE_THREAD },
  { name = "MUTATION_UNRESOLVE_THREAD", val = graphql.MUTATION_UNRESOLVE_THREAD },
  { name = "MUTATION_DELETE_REVIEW", val = graphql.MUTATION_DELETE_REVIEW },
  { name = "MUTATION_CREATE_AND_SUBMIT_REVIEW", val = graphql.MUTATION_CREATE_AND_SUBMIT_REVIEW },
}

h.run_test("All 10 GraphQL constants are strings", function()
  for _, c in ipairs(constants) do
    h.assert_equal("string", type(c.val), c.name .. " should be a string")
  end
end)

h.run_test("All GraphQL constants are non-empty", function()
  for _, c in ipairs(constants) do
    h.assert_true(#c.val > 0, c.name .. " should be non-empty")
  end
end)

h.run_test("QUERY_PR_DETAILS contains expected fragments", function()
  local q = graphql.QUERY_PR_DETAILS
  h.assert_match("pullRequest", q)
  h.assert_match("reviewThreads", q)
  h.assert_match("files", q)
  h.assert_match("reviews", q)
  h.assert_match("baseRefName", q)
  h.assert_match("headRefOid", q)
end)

h.run_test("QUERY_REVIEW_THREADS contains reviewThreads", function()
  h.assert_match("reviewThreads", graphql.QUERY_REVIEW_THREADS)
  h.assert_match("comments", graphql.QUERY_REVIEW_THREADS)
  h.assert_match("pullRequestReview", graphql.QUERY_REVIEW_THREADS)
end)

h.run_test("Mutations contain mutation keyword", function()
  h.assert_match("mutation", graphql.MUTATION_START_REVIEW)
  h.assert_match("mutation", graphql.MUTATION_SUBMIT_REVIEW)
  h.assert_match("mutation", graphql.MUTATION_ADD_REVIEW_THREAD)
  h.assert_match("mutation", graphql.MUTATION_ADD_REVIEW_COMMENT)
  h.assert_match("mutation", graphql.MUTATION_RESOLVE_THREAD)
  h.assert_match("mutation", graphql.MUTATION_UNRESOLVE_THREAD)
  h.assert_match("mutation", graphql.MUTATION_CREATE_AND_SUBMIT_REVIEW)
end)

h.run_test("Queries contain query keyword", function()
  h.assert_match("query", graphql.QUERY_PR_DETAILS)
  h.assert_match("query", graphql.QUERY_REVIEW_THREADS)
end)

h.run_test("MUTATION_ADD_REVIEW_THREAD has line/side/path params", function()
  local m = graphql.MUTATION_ADD_REVIEW_THREAD
  h.assert_match("%$path", m)
  h.assert_match("%$line", m)
  h.assert_match("%$side", m)
  h.assert_match("%$body", m)
end)

h.run_test("MUTATION_CREATE_AND_SUBMIT_REVIEW has event and pullRequestId params", function()
  local m = graphql.MUTATION_CREATE_AND_SUBMIT_REVIEW
  h.assert_match("%$pullRequestId", m)
  h.assert_match("%$event", m)
  h.assert_match("PullRequestReviewEvent", m)
end)

h.run_test("MUTATION_SUBMIT_REVIEW has event param", function()
  h.assert_match("%$event", graphql.MUTATION_SUBMIT_REVIEW)
  h.assert_match("PullRequestReviewEvent", graphql.MUTATION_SUBMIT_REVIEW)
end)

h.write_results("/tmp/gh_review_test_graphql.txt")
