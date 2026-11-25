-- Tests for thread buffer: content rendering, metadata, buffer options,
-- code context, and close behaviour.

local h = require("test.helpers")
local fixtures = require("test.fixtures")
local state = require("gh_review.state")
local thread = require("gh_review.thread")

local function setup_diff_buffers(path, num_lines)
  local left_name = "gh-review://LEFT/" .. path
  local right_name = "gh-review://RIGHT/" .. path

  local lines = {}
  for i = 1, num_lines do
    lines[i] = "line " .. i
  end

  vim.cmd("enew")
  local left = vim.fn.bufnr(left_name, true)
  vim.cmd("buffer " .. left)
  vim.bo[left].buftype = "nofile"
  vim.bo[left].swapfile = false
  vim.bo[left].bufhidden = "hide"
  vim.bo[left].modifiable = true
  vim.api.nvim_buf_set_lines(left, 0, -1, false, lines)
  vim.bo[left].modifiable = false
  state.set_left_bufnr(left)

  vim.cmd("enew")
  local right = vim.fn.bufnr(right_name, true)
  vim.cmd("buffer " .. right)
  vim.bo[right].buftype = "nofile"
  vim.bo[right].swapfile = false
  vim.bo[right].bufhidden = "hide"
  vim.bo[right].modifiable = true
  vim.api.nvim_buf_set_lines(right, 0, -1, false, lines)
  vim.bo[right].modifiable = false
  state.set_right_bufnr(right)
end

local function cleanup_diff_buffers()
  local left = state.get_left_bufnr()
  local right = state.get_right_bufnr()
  if left ~= -1 and vim.fn.bufexists(left) == 1 then
    vim.cmd("bwipeout! " .. left)
  end
  if right ~= -1 and vim.fn.bufexists(right) == 1 then
    vim.cmd("bwipeout! " .. right)
  end
  state.set_left_bufnr(-1)
  state.set_right_bufnr(-1)
end

h.run_test("Thread buffer: existing thread renders header and comments", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")

  local bufnr = state.get_thread_bufnr()
  h.assert_true(bufnr ~= -1, "thread bufnr should be set")
  h.assert_true(vim.fn.bufexists(bufnr) == 1, "thread buffer should exist")

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local all_text = table.concat(lines, "\n")

  h.assert_match("Thread on", lines[1])
  h.assert_match("src/new_file.ts", lines[1])
  h.assert_match(":10", lines[1])
  h.assert_match("%[Active%]", lines[1])

  h.assert_match("alice", all_text)
  h.assert_match("2025%-01%-15", all_text)
  h.assert_match("Looks good", all_text)

  h.assert_match("Reply below", all_text)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: resolved thread shows Resolved status", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_2")

  local bufnr = state.get_thread_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local all_text = table.concat(lines, "\n")

  h.assert_match("%[Resolved%]", lines[1])

  h.assert_match("bob", all_text)
  h.assert_match("Fix this", all_text)
  h.assert_match("alice", all_text)
  h.assert_match("Done", all_text)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: new comment renders New header", function()
  state.reset()
  setup_diff_buffers("src/test.ts", 20)
  state.set_diff_path("src/test.ts")

  thread.open_new("src/test.ts", 5, 5, "RIGHT", "placeholder")

  local bufnr = state.get_thread_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  h.assert_match("New comment on", lines[1])
  h.assert_match("src/test.ts", lines[1])
  h.assert_match(":5", lines[1])
  h.assert_match("%[New%]", lines[1])

  h.assert_true(vim.b[bufnr].gh_review_is_new)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: metadata variables set correctly", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  local bufnr = state.get_thread_bufnr()

  h.assert_equal("thread_1", vim.b[bufnr].gh_review_thread_id)
  h.assert_equal("src/new_file.ts", vim.b[bufnr].gh_review_path)
  h.assert_equal(10, vim.b[bufnr].gh_review_line)
  h.assert_equal("RIGHT", vim.b[bufnr].gh_review_side)
  h.assert_false(vim.b[bufnr].gh_review_is_new)
  h.assert_false(vim.b[bufnr].gh_review_is_resolved)
  h.assert_equal("comment_1", vim.b[bufnr].gh_review_first_comment_id)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: resolved thread metadata", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_2")
  local bufnr = state.get_thread_bufnr()

  h.assert_true(vim.b[bufnr].gh_review_is_resolved)
  h.assert_equal("comment_2", vim.b[bufnr].gh_review_first_comment_id)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: outdated thread falls back to originalLine", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/existing.ts", 30)
  state.set_diff_path("src/existing.ts")

  thread.open("thread_3")
  local bufnr = state.get_thread_bufnr()

  h.assert_equal(8, vim.b[bufnr].gh_review_line)
  local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  h.assert_match(":8", first_line)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: buffer options are correct", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  local bufnr = state.get_thread_bufnr()

  h.assert_equal("acwrite", vim.bo[bufnr].buftype)
  h.assert_equal("wipe", vim.bo[bufnr].bufhidden)
  h.assert_false(vim.bo[bufnr].swapfile)
  h.assert_equal("gh-review-thread", vim.bo[bufnr].filetype)
  local winid = vim.fn.bufwinid(bufnr)
  h.assert_true(vim.wo[winid].wrap)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: close cleans up state", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  h.assert_true(state.get_thread_bufnr() ~= -1, "thread bufnr should be set before close")

  thread.close_thread_buffer()

  h.assert_equal(-1, state.get_thread_bufnr(), "thread bufnr should be -1 after close")
  h.assert_equal(-1, state.get_thread_winid(), "thread winid should be -1 after close")

  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: initial body (suggestion) rendered", function()
  state.reset()
  setup_diff_buffers("src/test.ts", 20)
  state.set_diff_path("src/test.ts")

  local suggestion = "```suggestion\nsome code\n```"
  thread.open_new("src/test.ts", 5, 5, "RIGHT", suggestion)

  local bufnr = state.get_thread_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local all_text = table.concat(lines, "\n")

  h.assert_match("suggestion", all_text)
  h.assert_match("some code", all_text)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: code context from right buffer uses + prefix", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")

  local bufnr = state.get_thread_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local all_text = table.concat(lines, "\n")

  h.assert_match("10 %+", all_text)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: multi-line thread shows range context", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_2")

  local bufnr = state.get_thread_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local all_text = table.concat(lines, "\n")

  h.assert_match("20 %+", all_text)
  h.assert_match("25 %+", all_text)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: LEFT side uses - prefix in context", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/existing.ts", 30)
  state.set_diff_path("src/existing.ts")

  thread.open("thread_4")

  local bufnr = state.get_thread_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local all_text = table.concat(lines, "\n")

  h.assert_match("5 %-", all_text)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: date formatting strips time portion", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")

  local bufnr = state.get_thread_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local all_text = table.concat(lines, "\n")

  h.assert_match("2025%-01%-15", all_text)
  h.assert_false(all_text:find("T10:30"), "should not contain time portion")

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: opening new thread closes previous one", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  local first_bufnr = state.get_thread_bufnr()
  h.assert_true(first_bufnr ~= -1)

  thread.open("thread_2")
  local second_bufnr = state.get_thread_bufnr()
  h.assert_true(second_bufnr ~= -1)
  h.assert_false(vim.fn.bufexists(first_bufnr) == 1, "first thread buffer should be wiped")

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: close expands diff windows into freed space", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  state.set_diff_path("src/new_file.ts")

  local lines = {}
  for i = 1, 30 do
    lines[i] = "line " .. i
  end

  vim.cmd("enew")
  local right_bufnr = vim.fn.bufnr("gh-review://RIGHT/src/new_file.ts", true)
  vim.cmd("buffer " .. right_bufnr)
  vim.bo[right_bufnr].buftype = "nofile"
  vim.bo[right_bufnr].swapfile = false
  vim.bo[right_bufnr].bufhidden = "hide"
  vim.bo[right_bufnr].modifiable = true
  vim.wo.scrollbind = true
  vim.api.nvim_buf_set_lines(right_bufnr, 0, -1, false, lines)
  vim.bo[right_bufnr].modifiable = false
  state.set_right_bufnr(right_bufnr)

  vim.cmd("aboveleft vnew")
  local left_bufnr = vim.fn.bufnr("gh-review://LEFT/src/new_file.ts", true)
  vim.cmd("buffer " .. left_bufnr)
  vim.bo[left_bufnr].buftype = "nofile"
  vim.bo[left_bufnr].swapfile = false
  vim.bo[left_bufnr].bufhidden = "hide"
  vim.bo[left_bufnr].modifiable = true
  vim.wo.scrollbind = true
  vim.api.nvim_buf_set_lines(left_bufnr, 0, -1, false, lines)
  vim.bo[left_bufnr].modifiable = false
  state.set_left_bufnr(left_bufnr)

  thread.open("thread_1")

  local left_height_before = vim.fn.winheight(vim.fn.bufwinid(left_bufnr))
  local right_height_before = vim.fn.winheight(vim.fn.bufwinid(right_bufnr))

  thread.close_thread_buffer()

  local left_height_after = vim.fn.winheight(vim.fn.bufwinid(left_bufnr))
  local right_height_after = vim.fn.winheight(vim.fn.bufwinid(right_bufnr))
  h.assert_true(left_height_after > left_height_before, "left diff should be taller after thread close")
  h.assert_true(right_height_after > right_height_before, "right diff should be taller after thread close")

  vim.cmd("bwipeout! " .. left_bufnr)
  vim.cmd("bwipeout! " .. right_bufnr)
end)

h.run_test("Thread buffer: reply_start points to line after separator", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  local bufnr = state.get_thread_bufnr()
  local reply_start = vim.b[bufnr].gh_review_reply_start

  h.assert_true(reply_start > 0, "reply_start should be positive")

  local sep_line = vim.api.nvim_buf_get_lines(bufnr, reply_start - 2, reply_start - 1, false)[1]
  h.assert_match("Reply below", sep_line, "line before reply_start should be the separator")

  local reply_line = vim.api.nvim_buf_get_lines(bufnr, reply_start - 1, reply_start, false)[1]
  h.assert_equal("", reply_line, "reply_start line should be blank")

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: reply area is editable", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  local bufnr = state.get_thread_bufnr()
  local reply_start = vim.b[bufnr].gh_review_reply_start

  local winid = vim.fn.bufwinid(bufnr)
  vim.fn.win_gotoid(winid)
  vim.api.nvim_win_set_cursor(winid, { reply_start, 0 })
  vim.cmd("doautocmd CursorMoved")
  h.assert_true(vim.bo[bufnr].modifiable, "reply area should be modifiable")

  vim.api.nvim_buf_set_lines(bufnr, reply_start - 1, reply_start, false, { "Test reply text" })
  local written = vim.api.nvim_buf_get_lines(bufnr, reply_start - 1, reply_start, false)[1]
  h.assert_equal("Test reply text", written, "should be able to write in reply area")

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread buffer: header area is read-only", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  local bufnr = state.get_thread_bufnr()

  local winid = vim.fn.bufwinid(bufnr)
  vim.fn.win_gotoid(winid)
  vim.api.nvim_win_set_cursor(winid, { 1, 0 })
  vim.cmd("doautocmd CursorMoved")
  h.assert_false(vim.bo[bufnr].modifiable, "header area should not be modifiable")

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread omnifunc: findstart locates @ symbol", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  local bufnr = state.get_thread_bufnr()
  local reply_start = vim.b[bufnr].gh_review_reply_start

  local winid = vim.fn.bufwinid(bufnr)
  vim.fn.win_gotoid(winid)
  vim.api.nvim_win_set_cursor(winid, { reply_start, 0 })
  vim.cmd("doautocmd CursorMoved")

  -- Type "@al" at the reply line
  vim.api.nvim_buf_set_lines(bufnr, reply_start - 1, reply_start, false, { "@al" })
  vim.fn.cursor(reply_start, 4) -- position cursor after "@al"

  local col = thread.omnifunc(1, "")
  h.assert_equal(1, col, "findstart should return col of @")

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread omnifunc: base filtering returns matching participants", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())

  local matches = thread.omnifunc(0, "al")
  h.assert_equal(1, #matches, "should match alice")
  h.assert_equal("alice", matches[1])

  local all = thread.omnifunc(0, "")
  h.assert_equal(2, #all, "empty base should return all participants")
end)

h.run_test("Thread buffer: omnifunc is set", function()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")

  thread.open("thread_1")
  local bufnr = state.get_thread_bufnr()
  h.assert_match("omnifunc", vim.bo[bufnr].omnifunc)

  thread.close_thread_buffer()
  cleanup_diff_buffers()
end)

h.run_test("Thread: reply separator text follows configured keys", function()
  local config = require("gh_review.config")
  config.reset()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())

  thread.open_new("src/main.ts", 10, 10, "RIGHT", "")
  local bufnr = state.get_thread_bufnr()
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  h.assert_match("Ctrl%-S to submit", text, "default renders <C-s> as Ctrl-S")
  h.assert_match("Ctrl%-R to resolve", text)
  h.assert_match("Ctrl%-Q to cancel", text)
  thread.close_thread_buffer()

  config.setup({ keymaps = { thread = { submit = "<leader>s", resolve = false } } })
  thread.open_new("src/main.ts", 10, 10, "RIGHT", "")
  bufnr = state.get_thread_bufnr()
  text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  h.assert_match("<leader>s to submit", text, "remapped key shown verbatim")
  h.assert_true(text:find("to resolve") == nil, "disabled action omitted from the hint")
  h.assert_match("Reply below", text, "separator shape preserved for syntax matching")
  thread.close_thread_buffer()

  config.reset()
end)

h.run_test("Thread: keymaps honour configuration", function()
  local config = require("gh_review.config")
  config.reset()
  config.setup({ keymaps = { thread = { resolve = "Z", close_insert = false } } })

  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  thread.open_new("src/main.ts", 10, 10, "RIGHT", "")
  local bufnr = state.get_thread_bufnr()

  local function mapped(mode, lhs)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
      if m.lhs == lhs then return m end
    end
    return nil
  end

  h.assert_true(mapped("n", "Z") ~= nil, "resolve remapped")
  h.assert_true(mapped("n", "q") ~= nil, "close default intact")
  h.assert_true(mapped("i", "<C-Q>") == nil, "close_insert disabled in insert mode")
  h.assert_true(mapped("i", "<C-S>") ~= nil, "submit still bound in insert mode")

  thread.close_thread_buffer()
  config.reset()
end)

-- Comment actions (edit/delete) ------------------------------------------

-- Invoke a thread-buffer mapping's callback directly (avoids termcode
-- feedkeys issues in headless mode).
local function press(lhs)
  local bufnr = state.get_thread_bufnr()
  vim.fn.win_gotoid(vim.fn.bufwinid(bufnr))
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if m.lhs == lhs and m.callback then
      m.callback()
      return
    end
  end
  error("no normal-mode mapping for " .. lhs .. " on thread buffer")
end

local function buf_text()
  return table.concat(vim.api.nvim_buf_get_lines(state.get_thread_bufnr(), 0, -1, false), "\n")
end

-- Put the cursor on the first line matching `pattern`.
local function cursor_to(pattern)
  local bufnr = state.get_thread_bufnr()
  for i, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if l:find(pattern) then
      vim.api.nvim_win_set_cursor(vim.fn.bufwinid(bufnr), { i, 0 })
      return i
    end
  end
  error("no line matches " .. pattern)
end

local function cursor_line_text()
  return vim.api.nvim_get_current_line()
end

-- Replace the reply area (everything after the blank line below the
-- separator) with `text`.
local function set_reply(text)
  local bufnr = state.get_thread_bufnr()
  local start = vim.b[bufnr].gh_review_reply_start
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, start, -1, false, vim.split(text, "\n"))
end

-- Run `fn` with api.graphql and vim.ui.select stubbed. `opts.mutation` is the
-- canned (result, err) for the first non-refresh call; `opts.threads` is the
-- thread list the follow-up refresh returns; `opts.answer` is the confirm
-- choice. Returns every call made so tests can inspect variables.
local function with_stubs(opts, fn)
  local api = require("gh_review.api")
  local graphql = require("gh_review.graphql")
  local orig_graphql, orig_select, orig_notify = api.graphql, vim.ui.select, vim.notify
  local calls = { prompts = {}, notifications = {} }
  api.graphql = function(query, vars, callback)
    if query == graphql.QUERY_REVIEW_THREADS then
      calls[#calls + 1] = { kind = "refresh", vars = vars }
      callback({ data = { repository = { pullRequest = { reviewThreads = { nodes = opts.threads or {} } } } } })
    else
      calls[#calls + 1] = { kind = "mutation", query = query, vars = vars }
      local m = opts.mutation or {}
      callback(m.result, m.err)
    end
  end
  vim.ui.select = function(items, select_opts, on_choice)
    calls.prompts[#calls.prompts + 1] = select_opts.prompt
    on_choice(opts.answer)
  end
  vim.notify = function(msg) calls.notifications[#calls.notifications + 1] = msg end
  local ok, err = pcall(fn)
  api.graphql, vim.ui.select, vim.notify = orig_graphql, orig_select, orig_notify
  if not ok then error(err, 0) end
  return calls
end

-- Thread nodes with comment `id` removed from thread `thread_id`.
local function threads_without(thread_id, id)
  local nodes = fixtures.mock_thread_nodes()
  for _, t in ipairs(nodes) do
    if t.id == thread_id then
      t.comments.nodes = vim.tbl_filter(function(c) return c.id ~= id end, t.comments.nodes)
    end
  end
  return vim.tbl_filter(function(t) return #t.comments.nodes > 0 end, nodes)
end

local function open_thread(id)
  -- A failed test can leave a modified thread buffer behind; don't let it
  -- break the next test's setup.
  thread.close_thread_buffer()
  require("gh_review.config").reset()
  state.reset()
  state.set_pr(fixtures.mock_pr_data())
  state.set_threads(fixtures.mock_thread_nodes())
  setup_diff_buffers("src/new_file.ts", 30)
  state.set_diff_path("src/new_file.ts")
  thread.open(id)
end

local function close_thread()
  thread.close_thread_buffer()
  cleanup_diff_buffers()
end

h.run_test("Delete: gD deletes the comment under the cursor and redraws", function()
  open_thread("thread_2")
  cursor_to("^  Done")

  local calls = with_stubs({
    answer = "Yes",
    mutation = { result = { data = { deletePullRequestReviewComment = { pullRequestReview = { id = "rev_2" } } } } },
    threads = threads_without("thread_2", "comment_3"),
  }, function() press("gD") end)

  h.assert_equal("comment_3", calls[1].vars.id, "mutation targets the comment under the cursor")
  h.assert_equal("refresh", calls[2].kind, "threads fetched again after delete")
  h.assert_match("alice's comment", calls.prompts[1], "confirmation names the author")
  h.assert_true(state.get_thread_bufnr() ~= -1, "buffer stays open")
  h.assert_true(buf_text():find("Done") == nil, "deleted comment gone from the buffer")
  h.assert_match("Fix this", buf_text(), "other comments kept")
  h.assert_match("^bob", cursor_line_text(), "cursor lands on the comment that took its place")

  close_thread()
end)

h.run_test("Delete: key follows configuration and can be disabled", function()
  local config = require("gh_review.config")

  open_thread("thread_2")
  config.setup({ keymaps = { thread = { delete = "X" } } })
  close_thread()
  setup_diff_buffers("src/new_file.ts", 30)
  thread.open("thread_2")
  cursor_to("^  Done")
  local calls = with_stubs({ answer = "No" }, function() press("X") end)
  h.assert_equal(1, #calls.prompts, "remapped key deletes")
  close_thread()

  config.setup({ keymaps = { thread = { delete = false } } })
  setup_diff_buffers("src/new_file.ts", 30)
  thread.open("thread_2")
  local ok = pcall(press, "gD")
  h.assert_false(ok, "disabled action leaves no mapping")
  close_thread()

  config.reset()
end)

h.run_test("Delete: refused without permission, before any prompt or call", function()
  open_thread("thread_2")
  cursor_to("^  Fix this")

  local calls = with_stubs({ answer = "Yes" }, function() press("gD") end)

  h.assert_equal(0, #calls, "no API call")
  h.assert_equal(0, #calls.prompts, "no confirmation")
  h.assert_match("can't delete", calls.notifications[1])
  h.assert_match("Fix this", buf_text())

  close_thread()
end)

h.run_test("Delete: declining the confirmation sends nothing", function()
  open_thread("thread_2")
  cursor_to("^  Done")

  local calls = with_stubs({ answer = "No" }, function() press("gD") end)

  h.assert_equal(0, #calls, "no API call")
  h.assert_match("Done", buf_text())

  close_thread()
end)

h.run_test("Delete: cursor outside every comment does nothing", function()
  open_thread("thread_2")
  cursor_to("^Thread on")

  local calls = with_stubs({ answer = "Yes" }, function() press("gD") end)

  h.assert_equal(0, #calls, "no API call")
  h.assert_equal(0, #calls.prompts, "no confirmation")

  close_thread()
end)

h.run_test("Delete: removing the only comment closes the buffer", function()
  open_thread("thread_1")
  cursor_to("^  Looks good")

  with_stubs({
    answer = "Yes",
    mutation = { result = { data = { deletePullRequestReviewComment = {} } } },
    threads = threads_without("thread_1", "comment_1"),
  }, function() press("gD") end)

  h.assert_equal(-1, state.get_thread_bufnr(), "thread buffer closed")
  h.assert_true(next(state.get_thread("thread_1") or {}) == nil, "thread gone from state")

  cleanup_diff_buffers()
end)

h.run_test("Delete: failure leaves buffer and state unchanged", function()
  open_thread("thread_2")
  cursor_to("^  Done")
  local before = buf_text()

  local calls = with_stubs({ answer = "Yes", mutation = { err = "GraphQL error: boom" } },
    function() press("gD") end)

  h.assert_equal(1, #calls, "no refresh after a failed delete")
  h.assert_equal(before, buf_text(), "buffer unchanged")
  h.assert_equal(2, #state.get_thread("thread_2").comments.nodes, "state unchanged")

  close_thread()
end)

h.run_test("Delete: a draft reply survives the redraw", function()
  open_thread("thread_2")
  set_reply("my draft\nsecond line")
  cursor_to("^  Done")

  with_stubs({
    answer = "Yes",
    mutation = { result = { data = { deletePullRequestReviewComment = {} } } },
    threads = threads_without("thread_2", "comment_3"),
  }, function() press("gD") end)

  local bufnr = state.get_thread_bufnr()
  local reply = vim.api.nvim_buf_get_lines(bufnr, vim.b[bufnr].gh_review_reply_start, -1, false)
  h.assert_equal("my draft\nsecond line", table.concat(reply, "\n"), "draft kept below the separator")
  h.assert_match("Reply below", buf_text(), "still in reply mode")

  close_thread()
end)

-- Thread nodes with comment `id`'s body replaced.
local function threads_with_body(id, body)
  local nodes = fixtures.mock_thread_nodes()
  for _, t in ipairs(nodes) do
    for _, c in ipairs(t.comments.nodes) do
      if c.id == id then c.body = body end
    end
  end
  return nodes
end

local function reply_area()
  local bufnr = state.get_thread_bufnr()
  local lines = vim.api.nvim_buf_get_lines(bufnr, vim.b[bufnr].gh_review_reply_start, -1, false)
  return table.concat(lines, "\n")
end

h.run_test("Edit: ge loads the body and Ctrl-S saves it", function()
  open_thread("thread_2")
  cursor_to("^  Done")

  with_stubs({}, function() press("ge") end)
  h.assert_equal("Done", reply_area(), "body loaded below the separator")
  h.assert_match("── Editing alice's comment %(Ctrl%-S to save, Ctrl%-Q to cancel%) ──", buf_text())
  h.assert_equal("Done", cursor_line_text(), "cursor on the body")

  set_reply("Done, thanks")
  local calls = with_stubs({
    mutation = { result = { data = { updatePullRequestReviewComment = { pullRequestReviewComment = { id = "comment_3" } } } } },
    threads = threads_with_body("comment_3", "Done, thanks"),
  }, function() press("<C-S>") end)

  h.assert_equal("comment_3", calls[1].vars.pullRequestReviewCommentId)
  h.assert_equal("Done, thanks", calls[1].vars.body)
  h.assert_equal("refresh", calls[2].kind)
  h.assert_match("  Done, thanks", buf_text(), "new body rendered")
  h.assert_match("Reply below", buf_text(), "back to reply mode")
  h.assert_equal("", reply_area(), "reply area cleared")
  h.assert_match("^alice", cursor_line_text(), "cursor on the edited comment")

  close_thread()
end)

h.run_test("Edit: separator follows configured keys and keeps its highlight", function()
  open_thread("thread_2")
  require("gh_review.config").setup({ keymaps = { thread = { submit = "<leader>s", close_insert = false } } })
  close_thread()
  setup_diff_buffers("src/new_file.ts", 30)
  thread.open("thread_2")
  cursor_to("^  Done")
  with_stubs({}, function() press("ge") end)

  local lnum = cursor_to("^── Editing")
  h.assert_equal("── Editing alice's comment (<leader>s to save) ──", cursor_line_text())
  vim.cmd("syntax on")
  local group = vim.fn.synIDattr(vim.fn.synID(lnum, 5, 1), "name")
  h.assert_equal("ghThreadReplySep", group, "editing separator highlighted like the reply separator")

  close_thread()
  require("gh_review.config").reset()
end)

h.run_test("Edit: refused without permission", function()
  open_thread("thread_2")
  cursor_to("^  Fix this")

  local calls = with_stubs({}, function() press("ge") end)

  h.assert_match("can't edit", calls.notifications[1])
  h.assert_match("Reply below", buf_text(), "still in reply mode")

  close_thread()
end)

h.run_test("Edit: empty body is refused and names the delete key", function()
  open_thread("thread_2")
  cursor_to("^  Done")
  with_stubs({}, function() press("ge") end)
  set_reply("")

  local calls = with_stubs({}, function() press("<C-S>") end)

  h.assert_equal(0, #calls, "no API call")
  h.assert_match("empty; use gD to delete", calls.notifications[1])
  h.assert_match("Editing", buf_text(), "still editing")

  close_thread()
end)

h.run_test("Edit: unchanged body sends nothing", function()
  open_thread("thread_2")
  cursor_to("^  Done")
  with_stubs({}, function() press("ge") end)

  local calls = with_stubs({}, function() press("<C-S>") end)

  h.assert_equal(0, #calls, "no API call")

  close_thread()
end)

h.run_test("Edit: failure keeps the edit and the buffer", function()
  open_thread("thread_2")
  cursor_to("^  Done")
  with_stubs({}, function() press("ge") end)
  set_reply("Done, thanks")

  local calls = with_stubs({ mutation = { err = "GraphQL error: boom" } }, function() press("<C-S>") end)

  h.assert_equal(1, #calls, "no refresh after a failed save")
  h.assert_equal("Done, thanks", reply_area(), "edited text kept")
  h.assert_match("Editing", buf_text(), "still editing")

  close_thread()
end)

h.run_test("Edit: a draft reply is only discarded after confirmation", function()
  open_thread("thread_2")
  set_reply("my draft")
  cursor_to("^  Done")

  local calls = with_stubs({ answer = "No" }, function() press("ge") end)
  h.assert_match("Discard", calls.prompts[1])
  h.assert_equal("my draft", reply_area(), "draft kept on No")
  h.assert_match("Reply below", buf_text())

  cursor_to("^  Done")
  with_stubs({ answer = "Yes" }, function() press("ge") end)
  h.assert_equal("Done", reply_area(), "body loaded on Yes")
  h.assert_match("Editing", buf_text())

  close_thread()
end)

h.run_test("Edit: switching comments asks only when edits would be lost", function()
  open_thread("thread_2")
  state.get_thread("thread_2").comments.nodes[1].viewerCanUpdate = true

  cursor_to("^  Done")
  with_stubs({}, function() press("ge") end)
  cursor_to("^  Fix this")
  local calls = with_stubs({ answer = "No" }, function() press("ge") end)
  h.assert_equal(0, #calls.prompts, "untouched edit switches without asking")
  h.assert_match("Editing bob's comment", buf_text())

  set_reply("Fix this now")
  cursor_to("^  Done")
  calls = with_stubs({ answer = "No" }, function() press("ge") end)
  h.assert_equal(1, #calls.prompts, "changed edit asks first")
  h.assert_equal("Fix this now", reply_area(), "edit kept on No")

  close_thread()
end)

h.run_test("Edit: deleting the comment being edited warns and drops the edit", function()
  open_thread("thread_2")
  cursor_to("^  Done")
  with_stubs({}, function() press("ge") end)
  set_reply("Done, thanks")

  cursor_to("^  Done")
  local calls = with_stubs({
    answer = "Yes",
    mutation = { result = { data = { deletePullRequestReviewComment = {} } } },
    threads = threads_without("thread_2", "comment_3"),
  }, function() press("gD") end)

  h.assert_match("unsaved edits", calls.prompts[1])
  h.assert_match("Reply below", buf_text(), "edit mode ended")
  h.assert_equal("", reply_area(), "edit text dropped")

  close_thread()
end)

h.run_test("Edit: deleting another comment keeps the edit", function()
  open_thread("thread_2")
  state.get_thread("thread_2").comments.nodes[1].viewerCanDelete = true
  cursor_to("^  Done")
  with_stubs({}, function() press("ge") end)
  set_reply("Done, thanks")

  cursor_to("^  Fix this")
  local calls = with_stubs({
    answer = "Yes",
    mutation = { result = { data = { deletePullRequestReviewComment = {} } } },
    threads = threads_without("thread_2", "comment_2"),
  }, function() press("gD") end)

  h.assert_true(calls.prompts[1]:find("unsaved") == nil, "no warning for another comment")
  h.assert_match("Editing alice's comment", buf_text(), "still editing")
  h.assert_equal("Done, thanks", reply_area(), "edit text kept")

  close_thread()
end)

h.run_test("Edit: reopening the thread starts in reply mode", function()
  open_thread("thread_2")
  cursor_to("^  Done")
  with_stubs({}, function() press("ge") end)
  thread.close_thread_buffer()

  thread.open("thread_2")
  h.assert_match("Reply below", buf_text())

  close_thread()
end)

h.write_results("/tmp/gh_review_test_thread.txt")
