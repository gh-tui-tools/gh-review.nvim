-- Thread/comment buffer for viewing and replying to review threads.

local state = require("gh_review.state")
local api_mod = require("gh_review.api")
local graphql = require("gh_review.graphql")

local M = {}

local REPLY_SEPARATOR = "── Reply below (Ctrl-S to submit, Ctrl-R to resolve, Ctrl-Q to cancel) ──"

local function format_date(iso_date)
  -- "2024-01-15T10:30:00Z" -> "2024-01-15"
  return (iso_date:gsub("T.*", ""))
end

local function get_reply_text(bufnr, reply_start)
  if reply_start < 0 then return "" end
  local lines = vim.api.nvim_buf_get_lines(bufnr, reply_start - 1, -1, false)
  -- Trim leading blank lines
  while #lines > 0 and vim.trim(lines[1]) == "" do
    table.remove(lines, 1)
  end
  -- Trim trailing blank lines
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

local function submit_new_thread(body, bufnr)
  local path = vim.b[bufnr].gh_review_path or ""
  local line_num = vim.b[bufnr].gh_review_line or 0
  local start_line = vim.b[bufnr].gh_review_start_line
  local side = vim.b[bufnr].gh_review_side or "RIGHT"

  local vars = {
    pullRequestId = state.get_pr_id(),
    body = body,
    path = path,
    line = line_num,
    side = side,
  }

  if start_line and start_line ~= vim.NIL then
    vars.startLine = start_line
    vars.startSide = side
  end

  if state.is_review_active() then
    vars.pullRequestReviewId = state.get_pending_review_id()
  end

  print("Submitting comment...")
  api_mod.graphql(graphql.MUTATION_ADD_REVIEW_THREAD, vars, function(result)
    local new_thread = ((((result or {}).data or {}).addPullRequestReviewThread or {}).thread or {})
    if new_thread and new_thread.id then
      state.set_thread(new_thread.id, new_thread)
      require("gh_review.diff").refresh_signs()
      print("Comment submitted")
      M.close_thread_buffer()
    else
      vim.notify("[gh-review] Failed to create thread", vim.log.levels.ERROR)
    end
  end)
end

local function submit_review_reply(body, bufnr)
  local first_comment_id = vim.b[bufnr].gh_review_first_comment_id or ""
  if first_comment_id == "" then
    vim.notify("[gh-review] Cannot reply: no comment ID found", vim.log.levels.ERROR)
    return
  end

  print("Submitting reply...")
  local reply_vars = {
    pullRequestReviewId = state.get_pending_review_id(),
    threadId = first_comment_id,
    body = body,
  }
  api_mod.graphql(graphql.MUTATION_ADD_REVIEW_COMMENT, reply_vars, function(result)
    local comment = ((((result or {}).data or {}).addPullRequestReviewComment or {}).comment or {})
    if comment and comment.id then
      print("Reply submitted (pending review)")
      require("gh_review").refresh_threads()
      M.close_thread_buffer()
    else
      vim.notify("[gh-review] Failed to submit reply", vim.log.levels.ERROR)
    end
  end)
end

local function submit_reply_via_graphql(body, in_reply_to)
  local start_vars = { pullRequestId = state.get_pr_id() }
  api_mod.graphql(graphql.MUTATION_START_REVIEW, start_vars, function(result)
    local review = ((((result or {}).data or {}).addPullRequestReview or {}).pullRequestReview or {})
    if not review or not review.id then
      vim.notify("[gh-review] Failed to create review for reply", vim.log.levels.ERROR)
      return
    end
    local review_id = review.id

    local inner_vars = { pullRequestReviewId = review_id, threadId = in_reply_to, body = body }
    api_mod.graphql(graphql.MUTATION_ADD_REVIEW_COMMENT, inner_vars, function(_)
      local submit_vars = { reviewId = review_id, event = "COMMENT" }
      api_mod.graphql(graphql.MUTATION_SUBMIT_REVIEW, submit_vars, function(_)
        print("Reply submitted")
        require("gh_review").refresh_threads()
        M.close_thread_buffer()
      end)
    end)
  end)
end

local function submit_standalone_reply(body, bufnr)
  local first_comment_id = vim.b[bufnr].gh_review_first_comment_id or ""
  if first_comment_id == "" then
    vim.notify("[gh-review] Cannot reply: no comment ID found", vim.log.levels.ERROR)
    return
  end

  local owner = state.get_owner()
  local name = state.get_name()
  local pr_number = state.get_pr_number()

  print("Submitting reply...")
  api_mod.run_async(
    { "api", "-X", "POST",
      string.format("/repos/%s/%s/pulls/%d/comments/%s/replies", owner, name, pr_number, first_comment_id),
      "-f", "body=" .. body },
    function(stdout, stderr)
      if stderr and stderr ~= "" and not stdout:find('"id"') then
        submit_reply_via_graphql(body, first_comment_id)
        return
      end
      print("Reply submitted")
      require("gh_review").refresh_threads()
      M.close_thread_buffer()
    end)
end

local function submit_reply()
  local bufnr = state.get_thread_bufnr()
  if bufnr == -1 then return end
  local reply_start = vim.b[bufnr].gh_review_reply_start or -1
  local body = get_reply_text(bufnr, reply_start)
  if body == "" then
    print("No reply text to submit")
    return
  end

  local thread_id = vim.b[bufnr].gh_review_thread_id or ""
  local is_new = vim.b[bufnr].gh_review_is_new or false

  if is_new then
    submit_new_thread(body, bufnr)
  elseif state.is_review_active() then
    submit_review_reply(body, bufnr)
  else
    submit_standalone_reply(body, bufnr)
  end
end

local function toggle_resolve()
  local bufnr = state.get_thread_bufnr()
  if bufnr == -1 then return end
  local thread_id = vim.b[bufnr].gh_review_thread_id or ""
  if thread_id == "" then
    print("Cannot resolve: thread has not been created yet")
    return
  end

  local is_resolved = vim.b[bufnr].gh_review_is_resolved or false
  local mutation = is_resolved and graphql.MUTATION_UNRESOLVE_THREAD or graphql.MUTATION_RESOLVE_THREAD
  local action = is_resolved and "Unresolving" or "Resolving"

  print(action .. " thread...")
  local resolve_vars = { threadId = thread_id }
  api_mod.graphql(mutation, resolve_vars, function(result)
    local key = is_resolved and "unresolveReviewThread" or "resolveReviewThread"
    local updated = ((((result or {}).data or {})[key] or {}).thread or {})
    if updated and updated.id then
      local t = state.get_thread(thread_id)
      t.isResolved = updated.isResolved
      state.set_thread(thread_id, t)
      require("gh_review.diff").refresh_signs()
      print(is_resolved and "Thread unresolved" or "Thread resolved")
      M.close_thread_buffer()
    else
      vim.notify("[gh-review] Failed to " .. (is_resolved and "unresolve" or "resolve") .. " thread", vim.log.levels.ERROR)
    end
  end)
end

local function enforce_read_only()
  local bufnr = vim.api.nvim_get_current_buf()
  local reply_start = vim.b[bufnr].gh_review_reply_start or 999999
  if vim.fn.line(".") < reply_start then
    vim.bo[bufnr].modifiable = false
  else
    vim.bo[bufnr].modifiable = true
  end
end

function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.fn.getline(".")
    local col = vim.fn.col(".") - 1
    while col > 0 and line:sub(col, col) ~= "@" do
      col = col - 1
    end
    if col > 0 and line:sub(col, col) == "@" then
      return col
    end
    return -3
  end
  local participants = state.get_participants()
  local matches = {}
  for _, p in ipairs(participants) do
    if p:lower():find(base:lower(), 1, true) == 1 then
      matches[#matches + 1] = p
    end
  end
  return matches
end

local function show_thread(t)
  -- Close existing thread buffer if open
  M.close_thread_buffer()

  local path = state.get(t, "path", state.get_diff_path())
  local line_num = state.get(t, "line", nil)
  if not line_num or (type(line_num) == "number" and line_num <= 0) then
    line_num = state.get(t, "originalLine", 0)
  end
  local is_resolved = state.get(t, "isResolved", false)
  local thread_id = state.get(t, "id", "")
  local comments_obj = state.get(t, "comments", {})
  local comments = state.get(comments_obj, "nodes", {})
  local status_label = is_resolved and "Resolved" or "Active"
  local is_new = (thread_id == "")

  -- Build buffer content
  local lines = {}

  if is_new then
    lines[#lines + 1] = string.format("New comment on %s:%d  [New]", path, line_num)
  else
    lines[#lines + 1] = string.format("Thread on %s:%d  [%s]", path, line_num, status_label)
  end
  lines[#lines + 1] = string.rep("─", 60)

  -- Show code context (the line(s) being commented on)
  local side = state.get(t, "diffSide", "RIGHT")
  local context_bufnr = side == "LEFT" and state.get_left_bufnr() or state.get_right_bufnr()
  if context_bufnr ~= -1 and vim.fn.bufexists(context_bufnr) == 1 then
    local start_line = state.get(t, "startLine", nil)
    if not start_line then
      start_line = state.get(t, "originalStartLine", nil)
    end
    local ctx_start = start_line or line_num
    local ctx_end = line_num
    local prefix = side == "LEFT" and "-" or "+"
    local buf_lines = vim.api.nvim_buf_get_lines(context_bufnr, ctx_start - 1, ctx_end, false)
    for i, bl in ipairs(buf_lines) do
      lines[#lines + 1] = string.format("  %d %s │ %s", ctx_start + i - 1, prefix, bl)
    end
  end

  lines[#lines + 1] = string.rep("─", 60)
  lines[#lines + 1] = ""

  -- Show existing comments
  for _, c in ipairs(comments) do
    local author_obj = state.get(c, "author", {})
    local author = state.get(author_obj, "login", "unknown")
    local created = format_date(state.get(c, "createdAt", ""))
    lines[#lines + 1] = string.format("%s (%s):", author, created)
    local body = state.get(c, "body", "")
    body = body:gsub("\r", "")
    local body_lines = vim.split(body, "\n", { plain = true })
    for _, bl in ipairs(body_lines) do
      lines[#lines + 1] = "  " .. bl
    end
    lines[#lines + 1] = ""
  end

  -- Reply separator
  lines[#lines + 1] = REPLY_SEPARATOR
  lines[#lines + 1] = ""

  local reply_start = #lines

  local initial_body = state.get(t, "_initial_body", "")
  if initial_body ~= "" then
    local body_lines = vim.split(initial_body, "\n", { plain = true })
    for _, bl in ipairs(body_lines) do
      lines[#lines + 1] = bl
    end
  end

  -- Create buffer in a horizontal split below the current window
  vim.cmd("botright new")
  vim.cmd("resize 15")
  local buf_name = "gh-review://thread"
  local bufnr = vim.fn.bufnr(buf_name, true)
  vim.cmd("buffer " .. bufnr)
  state.set_thread_bufnr(bufnr)
  state.set_thread_winid(vim.fn.win_getid())

  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "gh-review-thread"
  local winid = vim.fn.win_getid()
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].wrap = true
  vim.wo[winid].winfixheight = true

  -- Set the buffer content
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Store metadata on the buffer
  vim.b[bufnr].gh_review_thread_id = thread_id
  vim.b[bufnr].gh_review_path = path
  vim.b[bufnr].gh_review_line = line_num
  vim.b[bufnr].gh_review_start_line = state.get(t, "startLine", vim.NIL)
  vim.b[bufnr].gh_review_side = side
  vim.b[bufnr].gh_review_reply_start = reply_start
  vim.b[bufnr].gh_review_is_new = is_new
  vim.b[bufnr].gh_review_is_resolved = is_resolved

  -- Store the first comment id (needed for REST reply)
  if #comments > 0 then
    vim.b[bufnr].gh_review_first_comment_id = comments[1].id
  end

  -- Make the header area read-only via autocmd
  local augroup = vim.api.nvim_create_augroup("gh_review_thread", { clear = false })
  vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = augroup,
    buffer = bufnr,
    callback = submit_reply,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    buffer = bufnr,
    callback = enforce_read_only,
  })

  -- Keymaps
  vim.keymap.set("n", "<C-s>", submit_reply, { buffer = bufnr, silent = true, desc = "Submit reply" })
  vim.keymap.set("i", "<C-s>", function() vim.cmd("stopinsert") submit_reply() end, { buffer = bufnr, silent = true, desc = "Submit reply" })
  vim.keymap.set("n", "<C-r>", toggle_resolve, { buffer = bufnr, silent = true, desc = "Toggle resolved" })
  vim.keymap.set("n", "q", function() M.close_thread_buffer() end, { buffer = bufnr, silent = true, desc = "Close thread" })
  vim.keymap.set("n", "<C-q>", function() M.close_thread_buffer() end, { buffer = bufnr, silent = true, desc = "Close thread" })
  vim.keymap.set("i", "<C-q>", function() vim.cmd("stopinsert") M.close_thread_buffer() end, { buffer = bufnr, silent = true, desc = "Close thread" })

  -- Set omnifunc for @-mention completion
  vim.bo[bufnr].omnifunc = "v:lua.require'gh_review.thread'.omnifunc"

  -- Position cursor at the reply area
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  if initial_body ~= "" then
    local target = math.min(reply_start + 2, total_lines)
    vim.api.nvim_win_set_cursor(0, { target, 0 })
  else
    vim.api.nvim_win_set_cursor(0, { math.min(reply_start, total_lines), 0 })
    if is_new then
      vim.cmd("startinsert")
    end
  end
end

-- Open an existing thread by id.
function M.open(thread_id)
  local t = state.get_thread(thread_id)
  if not t or not next(t) then
    vim.notify("[gh-review] Thread not found: " .. thread_id, vim.log.levels.ERROR)
    return
  end
  show_thread(t)
end

-- Open a new comment thread (no existing comments yet).
function M.open_new(path, start_line, end_line, side, initial_body)
  initial_body = initial_body or ""
  local pseudo_thread = {
    id = "",
    path = path,
    line = end_line,
    startLine = start_line ~= end_line and start_line or vim.NIL,
    diffSide = side,
    isResolved = false,
    comments = { nodes = {} },
    _initial_body = initial_body,
  }
  show_thread(pseudo_thread)
end

function M.close_thread_buffer()
  local bufnr = state.get_thread_bufnr()
  if bufnr ~= -1 and vim.fn.bufexists(bufnr) == 1 then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.fn.win_gotoid(winid)
      vim.bo[bufnr].modified = false
      vim.cmd("close")
    end
    if vim.fn.bufexists(bufnr) == 1 then
      vim.cmd("silent! bwipeout! " .. bufnr)
    end
  end
  state.set_thread_bufnr(-1)
  state.set_thread_winid(-1)

  -- Let diff windows expand into the freed space and redraw.
  vim.cmd("wincmd =")
  local left_winid = vim.fn.bufwinid(state.get_left_bufnr())
  if left_winid ~= -1 then
    vim.fn.win_gotoid(left_winid)
    vim.cmd([[execute "normal! \<C-e>\<C-y>"]])
  end
  local right_winid = vim.fn.bufwinid(state.get_right_bufnr())
  if right_winid ~= -1 then
    vim.fn.win_gotoid(right_winid)
    vim.cmd([[execute "normal! \<C-e>\<C-y>"]])
  end
end

return M
