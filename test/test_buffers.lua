-- Tests for buffer hygiene: the UI must not leave throwaway buffers behind.

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

h.write_results("/tmp/gh_review_test_buffers.txt")
