-- Tests for lua/gh_review/state.lua

local h = require("test.helpers")
local fixtures = require("test.fixtures")
local state = require("gh_review.state")

h.run_test("SetPR populates all getters", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())

  h.assert_equal("PR_abc123", state.get_pr_id())
  h.assert_equal(42, state.get_pr_number())
  h.assert_equal("Add feature X", state.get_pr_title())
  h.assert_equal("OPEN", state.get_pr_state())
  h.assert_equal("main", state.get_base_ref())
  h.assert_equal("aaa111", state.get_base_oid())
  h.assert_equal("feature-x", state.get_head_ref())
  h.assert_equal("bbb222", state.get_head_oid())
  h.assert_equal("testowner", state.get_head_repo_owner())
  h.assert_equal("testrepo", state.get_head_repo_name())
end)

h.run_test("SetPR loads changed files", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())

  local files = state.get_changed_files()
  h.assert_equal(3, #files)
  h.assert_equal("src/new_file.ts", files[1].path)
  h.assert_equal("ADDED", files[1].changeType)
  h.assert_equal(50, files[1].additions)
  h.assert_equal("src/existing.ts", files[2].path)
  h.assert_equal("MODIFIED", files[2].changeType)
  h.assert_equal("src/old_file.ts", files[3].path)
  h.assert_equal("DELETED", files[3].changeType)
end)

h.run_test("SetPR detects pending review", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())

  h.assert_true(state.is_review_active())
  h.assert_equal("pending_rev_1", state.get_pending_review_id())
end)

h.run_test("IsReviewActive false when no pending review", function()
  state.reset()
  local data = fixtures.mock_pr_data()
  data.data.repository.pullRequest.reviews.nodes = {}
  state.set_pr(data)

  h.assert_false(state.is_review_active())
  h.assert_equal("", state.get_pending_review_id())
end)

h.run_test("SetThreads and GetThreads", function()
  state.reset()
  state.set_threads(fixtures.mock_thread_nodes())

  local threads = state.get_threads()
  local count = 0
  for _ in pairs(threads) do count = count + 1 end
  h.assert_equal(4, count)
  h.assert_true(threads["thread_1"] ~= nil)
  h.assert_true(threads["thread_2"] ~= nil)
  h.assert_true(threads["thread_3"] ~= nil)
  h.assert_true(threads["thread_4"] ~= nil)
end)

h.run_test("GetThread returns correct data", function()
  state.reset()
  state.set_threads(fixtures.mock_thread_nodes())

  local t = state.get_thread("thread_1")
  h.assert_equal("thread_1", t.id)
  h.assert_equal(false, t.isResolved)
  h.assert_equal(10, t.line)
  h.assert_equal("RIGHT", t.diffSide)
  h.assert_equal("src/new_file.ts", t.path)
end)

h.run_test("GetThread returns empty for missing id", function()
  state.reset()
  state.set_threads(fixtures.mock_thread_nodes())

  local t = state.get_thread("nonexistent")
  h.assert_true(next(t) == nil)
end)

h.run_test("GetThreadsForFile filters correctly", function()
  state.reset()
  state.set_threads(fixtures.mock_thread_nodes())

  local new_file_threads = state.get_threads_for_file("src/new_file.ts")
  h.assert_equal(2, #new_file_threads)

  local existing_threads = state.get_threads_for_file("src/existing.ts")
  h.assert_equal(2, #existing_threads)

  local no_threads = state.get_threads_for_file("src/old_file.ts")
  h.assert_equal(0, #no_threads)

  local missing = state.get_threads_for_file("nonexistent.ts")
  h.assert_equal(0, #missing)
end)

h.run_test("SetThread adds/updates individual thread", function()
  state.reset()
  state.set_threads(fixtures.mock_thread_nodes())

  local new_thread = { id = "thread_new", isResolved = false, line = 99, diffSide = "RIGHT", path = "src/new_file.ts", comments = { nodes = {} } }
  state.set_thread("thread_new", new_thread)

  local t = state.get_thread("thread_new")
  h.assert_equal("thread_new", t.id)
  h.assert_equal(99, t.line)

  local updated = state.get_thread("thread_1")
  updated.isResolved = true
  state.set_thread("thread_1", updated)
  h.assert_equal(true, state.get_thread("thread_1").isResolved)
end)

h.run_test("Reset clears all state", function()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_merge_base_oid("merge123")
  state.set_diff_path("some/path.ts")
  state.set_files_bufnr(100)
  state.set_left_bufnr(300)
  state.set_right_bufnr(400)
  state.set_thread_bufnr(500)
  state.set_thread_winid(600)

  state.reset()

  h.assert_equal("", state.get_pr_id())
  h.assert_equal(0, state.get_pr_number())
  h.assert_equal("", state.get_pr_title())
  h.assert_equal("", state.get_pr_state())
  h.assert_equal("", state.get_base_ref())
  h.assert_equal("", state.get_base_oid())
  h.assert_equal("", state.get_head_ref())
  h.assert_equal("", state.get_head_oid())
  h.assert_equal("", state.get_head_repo_owner())
  h.assert_equal("", state.get_head_repo_name())
  h.assert_equal("", state.get_merge_base_oid())
  h.assert_equal("", state.get_owner())
  h.assert_equal("", state.get_name())
  h.assert_equal(0, #state.get_changed_files())
  h.assert_true(next(state.get_threads()) == nil)
  h.assert_equal("", state.get_pending_review_id())
  h.assert_false(state.is_review_active())
  h.assert_equal(-1, state.get_files_bufnr())
  h.assert_equal(-1, state.get_left_bufnr())
  h.assert_equal(-1, state.get_right_bufnr())
  h.assert_equal(-1, state.get_thread_bufnr())
  h.assert_equal(-1, state.get_thread_winid())
  h.assert_equal("", state.get_diff_path())
end)

h.run_test("Buffer/window setters and getters", function()
  state.reset()

  state.set_files_bufnr(10)
  h.assert_equal(10, state.get_files_bufnr())

  state.set_left_bufnr(30)
  h.assert_equal(30, state.get_left_bufnr())

  state.set_right_bufnr(40)
  h.assert_equal(40, state.get_right_bufnr())

  state.set_thread_bufnr(50)
  h.assert_equal(50, state.get_thread_bufnr())

  state.set_thread_winid(60)
  h.assert_equal(60, state.get_thread_winid())

  state.set_diff_path("foo/bar.ts")
  h.assert_equal("foo/bar.ts", state.get_diff_path())

  state.set_merge_base_oid("ccc333")
  h.assert_equal("ccc333", state.get_merge_base_oid())

  state.set_pending_review_id("rev_xyz")
  h.assert_equal("rev_xyz", state.get_pending_review_id())
  h.assert_true(state.is_review_active())
end)

h.run_test("SetPR populates head repo for fork PR", function()
  state.reset()
  state.set_pr(fixtures.mock_fork_pr_data())

  h.assert_equal("forkuser", state.get_head_repo_owner())
  h.assert_equal("testrepo", state.get_head_repo_name())
  h.assert_equal("fork-feature", state.get_head_ref())
end)

h.run_test("SetPR handles null headRepository (deleted fork)", function()
  state.reset()
  state.set_pr(fixtures.mock_deleted_fork_pr_data())

  h.assert_equal("PR_abc123", state.get_pr_id())
  h.assert_equal(42, state.get_pr_number())
  h.assert_equal("Add feature X", state.get_pr_title())
  h.assert_equal("main", state.get_base_ref())
  h.assert_equal("feature-x", state.get_head_ref())

  h.assert_equal("", state.get_head_repo_owner())
  h.assert_equal("", state.get_head_repo_name())
end)

h.run_test("SetThreads with empty list produces empty threads", function()
  state.reset()
  state.set_threads({})

  h.assert_true(next(state.get_threads()) == nil)
  h.assert_equal(0, #state.get_threads_for_file("any/file.ts"))
  h.assert_true(next(state.get_thread("nonexistent")) == nil)
end)

h.run_test("GetParticipants extracts unique sorted logins", function()
  state.reset()
  state.set_threads(fixtures.mock_thread_nodes())

  local participants = state.get_participants()
  h.assert_equal(2, #participants)
  h.assert_equal("alice", participants[1])
  h.assert_equal("bob", participants[2])
end)

h.run_test("GetParticipants returns empty for no threads", function()
  state.reset()
  state.set_threads({})

  local participants = state.get_participants()
  h.assert_equal(0, #participants)
end)

h.run_test("Statusline returns empty when no PR loaded", function()
  state.reset()
  local gh = require("gh_review")
  h.assert_equal("", gh.statusline())
end)

h.run_test("Statusline shows PR number when loaded", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  local gh = require("gh_review")
  local result = gh.statusline()
  h.assert_match("PR #42", result)
  h.assert_match("4 threads", result)
end)

h.run_test("Statusline shows reviewing when review active", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads({})
  local gh = require("gh_review")
  local result = gh.statusline()
  h.assert_match("reviewing", result)
end)

h.run_test("Statusline omits reviewing when no pending review", function()
  state.reset()
  local data = fixtures.mock_pr_data()
  data.data.repository.pullRequest.reviews.nodes = {}
  state.set_pr(data)
  state.set_threads({})
  local gh = require("gh_review")
  local result = gh.statusline()
  h.assert_match("PR #42", result)
  h.assert_false(result:find("reviewing"), "should not contain reviewing")
end)

h.run_test("Statusline singular thread", function()
  state.reset()
  local data = fixtures.mock_pr_data()
  data.data.repository.pullRequest.reviews.nodes = {}
  state.set_pr(data)
  state.set_threads({
    { id = "t1", isResolved = false, line = 1, diffSide = "RIGHT", path = "x.ts", comments = { nodes = {} } },
  })
  local gh = require("gh_review")
  local result = gh.statusline()
  h.assert_match("1 thread", result)
  h.assert_false(result:find("threads"), "should be singular")
end)

h.write_results("/tmp/gh_review_test_state.txt")
