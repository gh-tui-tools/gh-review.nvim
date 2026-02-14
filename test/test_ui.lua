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

h.write_results("/tmp/gh_review_test_ui.txt")
