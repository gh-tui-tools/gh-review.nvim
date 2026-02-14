-- Tests for diff sign placement and thread navigation logic.

local h = require("test.helpers")
local fixtures = require("test.fixtures")
local state = require("gh_review.state")
local diff = require("gh_review.diff")

-- Helper: create a scratch buffer with N lines of content.
local function setup_buffer(name, num_lines)
  local bufnr = vim.fn.bufnr(name, true)
  vim.cmd("buffer " .. bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  local lines = {}
  for i = 1, num_lines do
    lines[i] = "line " .. i
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.wo.signcolumn = "yes"
  return bufnr
end

-- Helper: get extmarks that have sign_text, simulating the old sign_getplaced API.
local function get_extmark_signs(bufnr)
  local ns = require("gh_review.state").ns
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
  local signs = {}
  for _, m in ipairs(marks) do
    local details = m[4] or {}
    if details.sign_text then
      signs[#signs + 1] = {
        lnum = m[2] + 1,  -- extmark rows are 0-indexed, signs were 1-indexed
        name = details.sign_hl_group,
        sign_text = details.sign_text,
      }
    end
  end
  return signs
end

h.run_test("Outdated threads use originalLine for sign placement", function()
  state.reset()

  vim.cmd("enew")
  local left = setup_buffer("gh-review://LEFT/src/existing.ts", 30)
  state.set_left_bufnr(left)
  vim.cmd("enew")
  local right = setup_buffer("gh-review://RIGHT/src/existing.ts", 30)
  state.set_right_bufnr(right)
  state.set_diff_path("src/existing.ts")

  state.set_threads(fixtures.mock_thread_nodes())

  diff.refresh_signs()

  local left_signs = get_extmark_signs(left)
  local right_signs = get_extmark_signs(right)

  h.assert_equal(1, #left_signs, "left buffer should have 1 sign")
  h.assert_equal(5, left_signs[1].lnum, "sign should be at line 5")

  h.assert_equal(1, #right_signs, "right buffer should have 1 sign from originalLine")
  h.assert_equal(8, right_signs[1].lnum, "sign should be at originalLine 8")

  vim.cmd("bwipeout! " .. left)
  vim.cmd("bwipeout! " .. right)
end)

h.run_test("Sign types: resolved, pending, normal", function()
  state.reset()

  vim.cmd("enew")
  local left = setup_buffer("gh-review://LEFT/src/new_file.ts", 50)
  state.set_left_bufnr(left)
  vim.cmd("enew")
  local right = setup_buffer("gh-review://RIGHT/src/new_file.ts", 50)
  state.set_right_bufnr(right)
  state.set_diff_path("src/new_file.ts")

  state.set_threads(fixtures.mock_thread_nodes())

  diff.refresh_signs()

  local right_signs = get_extmark_signs(right)
  table.sort(right_signs, function(a, b) return a.lnum < b.lnum end)

  h.assert_equal(2, #right_signs, "right buffer should have 2 signs")

  h.assert_equal(10, right_signs[1].lnum)
  h.assert_equal("GHReviewThread", right_signs[1].name)

  h.assert_equal(25, right_signs[2].lnum)
  h.assert_equal("GHReviewThreadResolved", right_signs[2].name)

  vim.cmd("bwipeout! " .. left)
  vim.cmd("bwipeout! " .. right)
end)

h.run_test("Pending review comment gets pending sign", function()
  state.reset()

  vim.cmd("enew")
  local left = setup_buffer("gh-review://LEFT/src/existing.ts", 30)
  state.set_left_bufnr(left)
  vim.cmd("enew")
  local right = setup_buffer("gh-review://RIGHT/src/existing.ts", 30)
  state.set_right_bufnr(right)
  state.set_diff_path("src/existing.ts")

  state.set_threads(fixtures.mock_thread_nodes())

  diff.refresh_signs()

  local left_signs = get_extmark_signs(left)
  h.assert_equal(1, #left_signs)
  h.assert_equal(5, left_signs[1].lnum)
  h.assert_equal("GHReviewThreadPending", left_signs[1].name)

  vim.cmd("bwipeout! " .. left)
  vim.cmd("bwipeout! " .. right)
end)

h.run_test("RefreshSigns does nothing when diff_path is empty", function()
  state.reset()
  diff.refresh_signs()
  h.assert_equal("", state.get_diff_path())
end)

h.run_test("Multiple signs placed at correct lines", function()
  state.reset()

  vim.cmd("enew")
  local left = setup_buffer("gh-review://LEFT/src/nav_test.ts", 50)
  state.set_left_bufnr(left)
  vim.cmd("enew")
  local right = setup_buffer("gh-review://RIGHT/src/nav_test.ts", 50)
  state.set_right_bufnr(right)
  state.set_diff_path("src/nav_test.ts")

  state.set_threads({
    { id = "nav_1", isResolved = false, isOutdated = false, line = 10, startLine = vim.NIL, diffSide = "RIGHT", path = "src/nav_test.ts", comments = { nodes = { { id = "c1", body = "x", author = { login = "a" }, createdAt = "2025-01-01T00:00:00Z", pullRequestReview = { id = "r1", state = "COMMENTED" } } } } },
    { id = "nav_2", isResolved = false, isOutdated = false, line = 25, startLine = vim.NIL, diffSide = "RIGHT", path = "src/nav_test.ts", comments = { nodes = { { id = "c2", body = "y", author = { login = "a" }, createdAt = "2025-01-01T00:00:00Z", pullRequestReview = { id = "r1", state = "COMMENTED" } } } } },
    { id = "nav_3", isResolved = false, isOutdated = false, line = 40, startLine = vim.NIL, diffSide = "RIGHT", path = "src/nav_test.ts", comments = { nodes = { { id = "c3", body = "z", author = { login = "a" }, createdAt = "2025-01-01T00:00:00Z", pullRequestReview = { id = "r1", state = "COMMENTED" } } } } },
  })

  diff.refresh_signs()

  local right_signs = get_extmark_signs(right)
  table.sort(right_signs, function(a, b) return a.lnum < b.lnum end)

  h.assert_equal(3, #right_signs, "should have 3 signs on RIGHT")
  h.assert_equal(10, right_signs[1].lnum)
  h.assert_equal(25, right_signs[2].lnum)
  h.assert_equal(40, right_signs[3].lnum)

  local left_signs = get_extmark_signs(left)
  h.assert_equal(0, #left_signs, "LEFT should have no signs")

  vim.cmd("bwipeout! " .. left)
  vim.cmd("bwipeout! " .. right)
end)

h.run_test("Editable buffer stores file path and mtime", function()
  state.reset()

  local tmpfile = "/tmp/gh_review_test_mtime.txt"
  vim.fn.writefile({ "line 1", "line 2", "line 3" }, tmpfile)
  local original_mtime = vim.fn.getftime(tmpfile)

  vim.cmd("enew")
  local left = setup_buffer("gh-review://LEFT/test_mtime.txt", 10)
  state.set_left_bufnr(left)
  vim.cmd("enew")
  local right_name = "gh-review://RIGHT/test_mtime.txt"
  local right = vim.fn.bufnr(right_name, true)
  vim.cmd("buffer " .. right)
  state.set_right_bufnr(right)
  state.set_diff_path("test_mtime.txt")
  state.set_local_checkout(true)

  vim.bo[right].buftype = "acwrite"
  vim.bo[right].bufhidden = "wipe"
  vim.bo[right].swapfile = false
  vim.bo[right].modifiable = true
  vim.api.nvim_buf_set_lines(right, 0, -1, false, { "line 1", "line 2", "line 3" })
  vim.bo[right].modified = false
  vim.b[right].gh_review_file_path = tmpfile
  vim.b[right].gh_review_file_mtime = original_mtime

  h.assert_equal(tmpfile, vim.b[right].gh_review_file_path)
  h.assert_equal(original_mtime, vim.b[right].gh_review_file_mtime)

  local buf_lines = vim.api.nvim_buf_get_lines(right, 0, -1, false)
  h.assert_equal("line 1", buf_lines[1])
  h.assert_equal("line 2", buf_lines[2])
  h.assert_equal("line 3", buf_lines[3])

  -- Simulate external change
  vim.loop.sleep(1100)
  vim.fn.writefile({ "changed line 1", "line 2", "line 3", "line 4" }, tmpfile)
  local new_mtime = vim.fn.getftime(tmpfile)
  h.assert_true(new_mtime > original_mtime, "mtime should increase after write")

  local cur_mtime = vim.fn.getftime(tmpfile)
  h.assert_true(cur_mtime > vim.b[right].gh_review_file_mtime, "should detect mtime change")

  -- Reload the content
  local new_content = vim.fn.readfile(tmpfile)
  vim.bo[right].modifiable = true
  vim.api.nvim_buf_set_lines(right, 0, -1, false, new_content)
  vim.bo[right].modified = false
  vim.b[right].gh_review_file_mtime = cur_mtime

  buf_lines = vim.api.nvim_buf_get_lines(right, 0, -1, false)
  h.assert_equal("changed line 1", buf_lines[1])
  h.assert_equal("line 4", buf_lines[4])
  h.assert_equal(new_mtime, vim.b[right].gh_review_file_mtime)

  vim.fn.delete(tmpfile)
  vim.cmd("bwipeout! " .. left)
  vim.cmd("bwipeout! " .. right)
end)

h.run_test("BufWriteCmd updates stored mtime", function()
  state.reset()

  local tmpfile = "/tmp/gh_review_test_write_mtime.txt"
  vim.fn.writefile({ "line 1", "line 2" }, tmpfile)
  local original_mtime = vim.fn.getftime(tmpfile)

  vim.cmd("enew")
  local left = setup_buffer("gh-review://LEFT/test_write.txt", 10)
  state.set_left_bufnr(left)
  vim.cmd("enew")
  local right = vim.fn.bufnr("gh-review://RIGHT/test_write.txt", true)
  vim.cmd("buffer " .. right)
  state.set_right_bufnr(right)
  state.set_diff_path("test_write.txt")
  state.set_local_checkout(true)

  vim.bo[right].buftype = "acwrite"
  vim.bo[right].bufhidden = "wipe"
  vim.bo[right].swapfile = false
  vim.bo[right].modifiable = true
  vim.api.nvim_buf_set_lines(right, 0, -1, false, { "line 1", "line 2" })
  vim.bo[right].modified = false
  vim.b[right].gh_review_file_path = tmpfile
  vim.b[right].gh_review_file_mtime = original_mtime

  -- Register BufWriteCmd
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = right,
    callback = function()
      vim.fn.writefile(vim.api.nvim_buf_get_lines(right, 0, -1, false), tmpfile)
      vim.bo[right].modified = false
      vim.b[right].gh_review_file_mtime = vim.fn.getftime(tmpfile)
    end,
  })

  vim.loop.sleep(1100)

  vim.cmd("silent write")

  local disk_mtime = vim.fn.getftime(tmpfile)
  local stored_mtime = vim.b[right].gh_review_file_mtime
  h.assert_equal(disk_mtime, stored_mtime, "stored mtime should match disk after :w")
  h.assert_true(stored_mtime > original_mtime, "stored mtime should have advanced")

  vim.fn.delete(tmpfile)
  vim.cmd("bwipeout! " .. left)
  vim.cmd("bwipeout! " .. right)
end)

h.run_test("Extmarks carry virtual text with author and body", function()
  state.reset()

  vim.cmd("enew")
  local left = setup_buffer("gh-review://LEFT/src/vt_test.ts", 30)
  state.set_left_bufnr(left)
  vim.cmd("enew")
  local right = setup_buffer("gh-review://RIGHT/src/vt_test.ts", 30)
  state.set_right_bufnr(right)
  state.set_diff_path("src/vt_test.ts")

  state.set_threads({
    { id = "vt1", isResolved = false, isOutdated = false, line = 10, originalLine = 10, startLine = vim.NIL, originalStartLine = vim.NIL, diffSide = "RIGHT", path = "src/vt_test.ts", comments = { nodes = { { id = "c1", body = "Looks good to me", author = { login = "alice" }, createdAt = "2025-01-15T10:30:00Z", pullRequestReview = { id = "r1", state = "COMMENTED" } } } } },
  })

  diff.refresh_signs()

  local ns = require("gh_review.state").ns
  local marks = vim.api.nvim_buf_get_extmarks(right, ns, 0, -1, { details = true })
  h.assert_equal(1, #marks, "should have 1 extmark")

  local details = marks[1][4]
  h.assert_true(details.virt_text ~= nil, "extmark should have virt_text")
  h.assert_equal(1, #details.virt_text, "virt_text should have 1 chunk")

  local text = details.virt_text[1][1]
  local hl = details.virt_text[1][2]
  h.assert_match("alice", text)
  h.assert_match("Looks good", text)
  h.assert_equal("GHReviewVirtText", hl)

  vim.cmd("bwipeout! " .. left)
  vim.cmd("bwipeout! " .. right)
end)

h.run_test("Virtual text truncates long bodies to 60 chars", function()
  state.reset()

  vim.cmd("enew")
  local left = setup_buffer("gh-review://LEFT/src/trunc.ts", 30)
  state.set_left_bufnr(left)
  vim.cmd("enew")
  local right = setup_buffer("gh-review://RIGHT/src/trunc.ts", 30)
  state.set_right_bufnr(right)
  state.set_diff_path("src/trunc.ts")

  local long_body = string.rep("x", 100)
  state.set_threads({
    { id = "tr1", isResolved = false, isOutdated = false, line = 5, originalLine = 5, startLine = vim.NIL, originalStartLine = vim.NIL, diffSide = "RIGHT", path = "src/trunc.ts", comments = { nodes = { { id = "c1", body = long_body, author = { login = "bob" }, createdAt = "2025-01-15T10:30:00Z", pullRequestReview = { id = "r1", state = "COMMENTED" } } } } },
  })

  diff.refresh_signs()

  local ns = require("gh_review.state").ns
  local marks = vim.api.nvim_buf_get_extmarks(right, ns, 0, -1, { details = true })
  local text = marks[1][4].virt_text[1][1]
  -- "bob: " is 5 chars, truncated body is 57 + "..." = 60, total <= 65
  h.assert_true(#text <= 66, "virtual text should be truncated (got " .. #text .. " chars)")
  h.assert_match("%.%.%.", text, "should end with ellipsis")

  vim.cmd("bwipeout! " .. left)
  vim.cmd("bwipeout! " .. right)
end)

h.write_results("/tmp/gh_review_test_diff_logic.txt")
