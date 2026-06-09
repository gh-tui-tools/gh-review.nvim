-- Tests for UI: files list buffer and diff buffer creation.

local h = require("test.helpers")
local fixtures = require("test.fixtures")
local state = require("gh_review.state")
local files = require("gh_review.files")

h.run_test("Files list: Open creates buffer with correct content", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  files.open()

  local bufnr = state.get_files_bufnr()
  h.assert_true(bufnr ~= -1, "files bufnr should be set")
  h.assert_true(vim.fn.bufexists(bufnr) == 1, "files buffer should exist")

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.assert_true(#lines >= 6, "should have header + 3 file lines")

  h.assert_match("https://github.com/test%-owner/test%-repo/pull/42", lines[1])
  h.assert_match("Add feature X", lines[1])
  h.assert_match("Files changed %(3%)", lines[2])
  h.assert_equal("", lines[3])

  h.assert_match("src/new_file.ts", lines[4])
  h.assert_match("src/existing.ts", lines[5])
  h.assert_match("src/old_file.ts", lines[6])

  h.assert_match("A", lines[4])
  h.assert_match("M", lines[5])
  h.assert_match("D", lines[6])

  h.assert_match("%[2 threads%]", lines[4])
  h.assert_match("%[2 threads%]", lines[5])

  files.close()
end)

h.run_test("Files list: Toggle opens and closes", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  files.toggle()
  local bufnr = state.get_files_bufnr()
  h.assert_true(bufnr ~= -1 and vim.fn.bufexists(bufnr) == 1, "buffer should exist after toggle on")
  h.assert_true(vim.fn.bufwinid(bufnr) ~= -1, "buffer should be visible after toggle on")

  files.toggle()
  h.assert_equal(-1, vim.fn.bufwinid(bufnr), "buffer should not be visible after toggle off")

  files.toggle()
  h.assert_true(vim.fn.bufwinid(bufnr) ~= -1, "buffer should be visible after second toggle on")

  files.close()
end)

h.run_test("Files list: buffer options are correct", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  files.open()
  local bufnr = state.get_files_bufnr()

  h.assert_equal("nofile", vim.bo[bufnr].buftype)
  h.assert_equal("hide", vim.bo[bufnr].bufhidden)
  h.assert_false(vim.bo[bufnr].swapfile)
  h.assert_false(vim.bo[bufnr].modifiable)
  h.assert_equal("gh-review-files", vim.bo[bufnr].filetype)

  files.close()
end)

h.run_test("Files list: additions and deletions shown", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  files.open()
  local bufnr = state.get_files_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  h.assert_match("%+50", lines[4])
  h.assert_match("%-0", lines[4])
  h.assert_match("%+10", lines[5])
  h.assert_match("%-5", lines[5])
  h.assert_match("%+0", lines[6])
  h.assert_match("%-30", lines[6])

  files.close()
end)

h.run_test("Files list: Rerender updates content", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  files.open()
  local bufnr = state.get_files_bufnr()

  state.set_thread("thread_extra", { id = "thread_extra", isResolved = false, isOutdated = false, line = 1, startLine = vim.NIL, diffSide = "RIGHT", path = "src/old_file.ts", comments = { nodes = {} } })

  files.rerender()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.assert_match("%[1 thread%]", lines[6])

  files.close()
end)

h.run_test("Files list: Close expands diff windows into freed space", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  files.open()
  local files_bufnr = state.get_files_bufnr()
  local files_winid = vim.fn.bufwinid(files_bufnr)
  h.assert_true(files_winid ~= -1, "files window should exist")

  vim.fn.win_gotoid(files_winid)
  vim.cmd("aboveleft new")
  local right_bufnr = vim.fn.bufnr("gh-review://RIGHT/test.ts", true)
  vim.cmd("buffer " .. right_bufnr)
  vim.bo[right_bufnr].buftype = "nofile"
  vim.wo.scrollbind = true
  state.set_right_bufnr(right_bufnr)

  vim.cmd("aboveleft vnew")
  local left_bufnr = vim.fn.bufnr("gh-review://LEFT/test.ts", true)
  vim.cmd("buffer " .. left_bufnr)
  vim.bo[left_bufnr].buftype = "nofile"
  vim.wo.scrollbind = true
  state.set_left_bufnr(left_bufnr)

  local left_height_before = vim.fn.winheight(vim.fn.bufwinid(left_bufnr))
  local right_height_before = vim.fn.winheight(vim.fn.bufwinid(right_bufnr))

  files.close()

  h.assert_equal(-1, vim.fn.bufwinid(files_bufnr), "files window should be closed")

  local left_height_after = vim.fn.winheight(vim.fn.bufwinid(left_bufnr))
  local right_height_after = vim.fn.winheight(vim.fn.bufwinid(right_bufnr))
  h.assert_true(left_height_after > left_height_before, "left diff should be taller after close")
  h.assert_true(right_height_after > right_height_before, "right diff should be taller after close")

  vim.cmd("bwipeout! " .. left_bufnr)
  vim.cmd("bwipeout! " .. right_bufnr)
end)

h.run_test("Files list: gf keymap closes the files list", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  files.open()
  local bufnr = state.get_files_bufnr()
  h.assert_true(vim.fn.bufwinid(bufnr) ~= -1, "files window should be visible")

  local winid = vim.fn.bufwinid(bufnr)
  vim.fn.win_gotoid(winid)
  vim.cmd("normal gf")

  h.assert_equal(-1, vim.fn.bufwinid(bufnr), "files window should be closed after gf")
end)

h.run_test("Files list: all change type flags rendered correctly", function()
  state.reset()
  state.set_pr(fixtures.mock_all_change_types_pr_data())
  state.set_threads({})
  state.set_repo_info("test-owner", "test-repo")

  files.open()
  local bufnr = state.get_files_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  h.assert_match("Files changed %(5%)", lines[2])

  h.assert_match("%sA%s", lines[4], "ADDED should show A flag")
  h.assert_match("%sM%s", lines[5], "MODIFIED should show M flag")
  h.assert_match("%sD%s", lines[6], "DELETED should show D flag")
  h.assert_match("%sR%s", lines[7], "RENAMED should show R flag")
  h.assert_match("%sC%s", lines[8], "COPIED should show C flag")

  files.close()
end)

h.run_test("Files list: checkbox reflects checked state", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  files.open()
  local bufnr = state.get_files_bufnr()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.assert_match("^%[ %]", lines[4], "unchecked file renders [ ]")

  state.set_file_checked("src/new_file.ts", true)
  files.rerender()

  lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  h.assert_match("^%[x%]", lines[4], "checked file renders [x]")
  h.assert_match("^%[ %]", lines[5], "other files stay unchecked")

  files.close()
end)

h.run_test("Files list: viewed state hydrated from viewerViewedState", function()
  state.reset()
  local data = fixtures.mock_pr_data()
  data.data.repository.pullRequest.files.nodes[2].viewerViewedState = "VIEWED"
  state.set_pr(data)
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")

  h.assert_true(state.is_file_checked("src/existing.ts"), "VIEWED file should be checked")
  h.assert_false(state.is_file_checked("src/new_file.ts"), "non-VIEWED file should be unchecked")

  files.close()
end)

-- Invoke the buffer's <Space> mapping callback with the cursor on the given
-- 1-indexed row. Calling the mapping's RHS directly avoids fragile termcode
-- feedkeys handling in headless mode.
local function press_space(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  vim.fn.win_gotoid(winid)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if m.lhs == " " and m.callback then
      m.callback()
      return
    end
  end
  error("no <Space> mapping found on files buffer")
end

-- Drive the <Space> toggle with the cursor on the given 1-indexed file row,
-- using a stubbed api.graphql whose response is controlled by `response`.
local function toggle_file_row(row, response)
  local api = require("gh_review.api")
  local original = api.graphql
  local captured = {}
  api.graphql = function(query, vars, callback)
    captured.vars = vars
    callback(response.result, response.err)
  end

  local bufnr = state.get_files_bufnr()
  vim.api.nvim_win_set_cursor(vim.fn.bufwinid(bufnr), { row, 0 })
  press_space(bufnr)

  api.graphql = original
  return captured
end
h.run_test("Files list: toggle marks file viewed and persists on success", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")
  files.open()

  local captured = toggle_file_row(4, { result = { data = { markFileAsViewed = { pullRequest = { id = "PR_abc123" } } } } })

  h.assert_equal("src/new_file.ts", captured.vars.path, "mutation sent for the file under cursor")
  h.assert_equal("PR_abc123", captured.vars.pullRequestId, "mutation includes PR id")
  h.assert_true(state.is_file_checked("src/new_file.ts"), "file stays checked after successful mutation")

  local lines = vim.api.nvim_buf_get_lines(state.get_files_bufnr(), 0, -1, false)
  h.assert_match("^%[x%]", lines[4], "checkbox shows checked after success")

  files.close()
end)

h.run_test("Files list: toggle reverts optimistic state on failure", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")
  files.open()

  toggle_file_row(4, { result = nil, err = "GraphQL error: boom" })

  h.assert_false(state.is_file_checked("src/new_file.ts"), "failed mutation reverts to unchecked")
  local lines = vim.api.nvim_buf_get_lines(state.get_files_bufnr(), 0, -1, false)
  h.assert_match("^%[ %]", lines[4], "checkbox shows unchecked after failure")

  files.close()
end)

h.run_test("Files list: toggle on header line is a no-op", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_repo_info("test-owner", "test-repo")
  files.open()

  local called = false
  local api = require("gh_review.api")
  local original = api.graphql
  api.graphql = function() called = true end

  local bufnr = state.get_files_bufnr()
  vim.api.nvim_win_set_cursor(vim.fn.bufwinid(bufnr), { 2, 0 })
  press_space(bufnr)

  api.graphql = original
  h.assert_false(called, "toggling on a header line should not call the API")

  files.close()
end)

h.write_results("/tmp/gh_review_test_ui.txt")
