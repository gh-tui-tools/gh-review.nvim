-- Tests for buffer and window teardown: the UI must not leave throwaway
-- buffers behind, and closing it must never strand the plugin half-open.

local h = require("test.helpers")
local fixtures = require("test.fixtures")
local state = require("gh_review.state")
local files = require("gh_review.files")
local thread = require("gh_review.thread")

-- Buffers with no name and no content. Opening a split with :new creates one of
-- these and then abandons it when the window is pointed at the real buffer.
local function stray_count()
  local n = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == "" then
      local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
      if #lines == 0 or (#lines == 1 and lines[1] == "") then n = n + 1 end
    end
  end
  return n
end

local function load_pr()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")
end

h.run_test("Buffers: opening the files list strands nothing", function()
  load_pr()
  local before = stray_count()
  files.open()
  h.assert_equal(before, stray_count(), "files list split must not orphan an empty buffer")
  files.close()
end)

h.run_test("Buffers: reopening the files list does not accumulate strays", function()
  load_pr()
  files.open()
  local after_first = stray_count()
  files.close()
  files.open()
  h.assert_equal(after_first, stray_count(), "second open must not add another stray")
  files.close()
end)

h.run_test("Buffers: opening a thread strands nothing", function()
  load_pr()
  local before = stray_count()
  thread.open_new("src/main.ts", 10, 10, "RIGHT", "")
  h.assert_equal(before, stray_count(), "thread split must not orphan an empty buffer")
  thread.close_thread_buffer()
end)

h.run_test("Buffers: a full open/close cycle returns to the starting count", function()
  load_pr()
  local before = stray_count()
  files.open()
  thread.open_new("src/main.ts", 10, 10, "RIGHT", "")
  thread.close_thread_buffer()
  files.close()
  h.assert_equal(before, stray_count(), "cycle must not leak buffers")
end)

-- :close raises E444 on the last window. Every teardown path has to survive
-- that, because the files list being the only window is an ordinary way to sit
-- in a review -- and because an error there aborts M.close() before it wipes
-- buffers and resets state, leaving the plugin half-open with no way back.

h.run_test("Teardown: closing the files list as the only window does not error", function()
  load_pr()
  files.open()
  vim.cmd("only")
  h.assert_equal(1, #vim.api.nvim_list_wins(), "files list is the only window")

  local ok, err = pcall(files.close)

  h.assert_true(ok, "files.close must not raise: " .. tostring(err))
  h.assert_true(#vim.api.nvim_list_wins() >= 1, "a window must survive")
  local shown = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
  h.assert_true(shown:match("^gh%-review://") == nil, "window no longer shows a review buffer")
end)

h.run_test("Teardown: closing a thread as the only window does not error", function()
  load_pr()
  thread.open_new("src/main.ts", 10, 10, "RIGHT", "")
  vim.cmd("only")

  local ok, err = pcall(thread.close_thread_buffer)

  h.assert_true(ok, "close_thread_buffer must not raise: " .. tostring(err))
  h.assert_equal(-1, state.get_thread_bufnr(), "thread state cleared")
end)

h.run_test("Teardown: GHReviewClose completes from a single window", function()
  load_pr()
  files.open()
  vim.cmd("only")

  local ok, err = pcall(require("gh_review").close)

  h.assert_true(ok, "close must not raise: " .. tostring(err))
  h.assert_equal(-1, state.get_files_bufnr(), "state.reset() ran")
  h.assert_equal("", state.get_pr_id(), "PR state cleared")

  local leftover = 0
  for _, bi in ipairs(vim.fn.getbufinfo()) do
    if bi.name:match("^gh%-review://") then leftover = leftover + 1 end
  end
  h.assert_equal(0, leftover, "every review buffer was wiped")
end)

h.run_test("Teardown: a normal multi-window close still closes the window", function()
  load_pr()
  files.open()
  local before = #vim.api.nvim_list_wins()
  h.assert_true(before > 1, "more than one window open")

  files.close()

  h.assert_equal(before - 1, #vim.api.nvim_list_wins(), "the files window was closed, not emptied")
end)

h.write_results("/tmp/gh_review_test_buffers.txt")
