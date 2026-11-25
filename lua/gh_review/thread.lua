-- Thread/comment buffer for viewing and replying to review threads.

local state = require("gh_review.state")
local api_mod = require("gh_review.api")
local graphql = require("gh_review.graphql")
local config = require("gh_review.config")
local win = require("gh_review.win")

local M = {}

-- Render a configured lhs for display. <C-s> reads better as Ctrl-S, and this
-- keeps the default separator byte-identical to what syntax/gh-review-thread.vim
-- and the help file describe.
local function key_hint(lhs)
  local ctrl = lhs:match("^<[Cc]%-(.)>$")
  if ctrl then return "Ctrl-" .. ctrl:upper() end
  return lhs
end

-- The comment being edited in the reply area, as { id, body, author }, or
-- nil in reply mode. There is only ever one thread buffer.
local editing = nil

-- The separator names the keys that act on the reply, so it has to follow
-- configuration. Disabled actions are omitted rather than shown as unusable.
-- The "── Reply below ... ──" and "── Editing ... ──" shapes are
-- load-bearing: gh-review-thread.vim matches on them.
local function reply_separator()
  local km = config.options.keymaps.thread
  local title, pairs_
  if editing then
    title = string.format("Editing %s's comment", editing.author)
    pairs_ = { { km.submit, "save" }, { km.close_insert, "cancel" } }
  else
    title = "Reply below"
    pairs_ = { { km.submit, "submit" }, { km.resolve, "resolve" }, { km.close_insert, "cancel" } }
  end
  local hints = {}
  for _, pair in ipairs(pairs_) do
    if type(pair[1]) == "string" then
      hints[#hints + 1] = string.format("%s to %s", key_hint(pair[1]), pair[2])
    end
  end
  if #hints == 0 then
    return "── " .. title .. " ──"
  end
  return "── " .. title .. " (" .. table.concat(hints, ", ") .. ") ──"
end

local function format_date(iso_date)
  -- "2024-01-15T10:30:00Z" -> "2024-01-15"
  return (iso_date:gsub("T.*", ""))
end

local REACTION_EMOJI = {
  THUMBS_UP = "👍",
  THUMBS_DOWN = "👎",
  LAUGH = "😄",
  HOORAY = "🎉",
  CONFUSED = "😕",
  HEART = "❤️",
  ROCKET = "🚀",
  EYES = "👀",
}

local function format_reactions(comment)
  local groups = state.get(comment, "reactionGroups", {})
  if type(groups) ~= "table" or #groups == 0 then return nil end
  local parts = {}
  for _, g in ipairs(groups) do
    local content = state.get(g, "content", "")
    local reactors = state.get(g, "reactors", {})
    local count = state.get(reactors, "totalCount", 0)
    if count > 0 then
      local emoji = REACTION_EMOJI[content] or content
      parts[#parts + 1] = emoji .. " " .. count
    end
  end
  if #parts == 0 then return nil end
  return "  " .. table.concat(parts, "  ")
end

-- "alice (2025-01-15):", or "alice (2025-01-15, edited):" once edited.
-- Shared with the floating preview.
function M.author_line(comment)
  local author = state.get(state.get(comment, "author", {}), "login", "unknown")
  local created = format_date(state.get(comment, "createdAt", ""))
  local edited = state.get(comment, "lastEditedAt", nil) and ", edited" or ""
  return string.format("%s (%s%s):", author, created, edited)
end

-- Drop leading and trailing blank lines.
local function trim_blank_lines(lines)
  while #lines > 0 and vim.trim(lines[1]) == "" do
    table.remove(lines, 1)
  end
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

local function get_reply_text(bufnr, reply_start)
  if reply_start < 0 then return "" end
  return trim_blank_lines(vim.api.nvim_buf_get_lines(bufnr, reply_start - 1, -1, false))
end

-- A comment body as it would read back from the reply area, so an untouched
-- edit compares equal to the original.
local function normalize_body(body)
  return trim_blank_lines(vim.split(body:gsub("\r", ""), "\n", { plain = true }))
end

-- Line ranges of the rendered comments, so actions can find the comment under
-- the cursor. Each entry is { first = lnum, last = lnum, comment = node }.
-- There is only ever one thread buffer, so module state is enough.
local comment_ranges = {}

-- Build the thread buffer's lines. `reply_text` pre-fills the reply area.
-- Returns lines, the reply area's first line, and the comment ranges.
local function build_lines(t, reply_text)
  local path = state.get(t, "path", state.get_diff_path())
  local line_num = state.get(t, "line", nil)
  if not line_num or (type(line_num) == "number" and line_num <= 0) then
    line_num = state.get(t, "originalLine", 0)
  end
  local is_resolved = state.get(t, "isResolved", false)
  local comments = state.get(state.get(t, "comments", {}), "nodes", {})
  local is_new = (state.get(t, "id", "") == "")

  local lines = {}

  if is_new then
    lines[#lines + 1] = string.format("New comment on %s:%d  [New]", path, line_num)
  else
    lines[#lines + 1] = string.format("Thread on %s:%d  [%s]", path, line_num,
      is_resolved and "Resolved" or "Active")
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

  local ranges = {}
  for _, c in ipairs(comments) do
    local first = #lines + 1
    lines[#lines + 1] = M.author_line(c)
    local body = state.get(c, "body", ""):gsub("\r", "")
    for _, bl in ipairs(vim.split(body, "\n", { plain = true })) do
      lines[#lines + 1] = "  " .. bl
    end
    local reaction_line = format_reactions(c)
    if reaction_line then
      lines[#lines + 1] = reaction_line
    end
    ranges[#ranges + 1] = { first = first, last = #lines, comment = c }
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = reply_separator()
  lines[#lines + 1] = ""

  local reply_start = #lines

  if reply_text ~= "" then
    for _, bl in ipairs(vim.split(reply_text, "\n", { plain = true })) do
      lines[#lines + 1] = bl
    end
  end

  return lines, reply_start, ranges
end

-- Write `t` into the thread buffer and refresh the metadata actions rely on.
local function render(bufnr, t, reply_text)
  local lines, reply_start, ranges = build_lines(t, reply_text)
  local comments = state.get(state.get(t, "comments", {}), "nodes", {})

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modified = false
  comment_ranges = ranges

  vim.b[bufnr].gh_review_thread_id = state.get(t, "id", "")
  vim.b[bufnr].gh_review_path = state.get(t, "path", state.get_diff_path())
  vim.b[bufnr].gh_review_reply_start = reply_start
  vim.b[bufnr].gh_review_is_new = (state.get(t, "id", "") == "")
  vim.b[bufnr].gh_review_is_resolved = state.get(t, "isResolved", false)
  -- The first comment id is needed for REST replies; it changes when the
  -- root comment is deleted.
  vim.b[bufnr].gh_review_first_comment_id = #comments > 0 and comments[1].id or nil
  return reply_start
end

-- Redraw the open thread buffer from state after a server-side change. The
-- cursor goes to comment `focus_id`, or failing that to the comment now at
-- `focus_index`. Unsent text in the reply area survives the redraw unless
-- `reply_text` replaces it, or the comment being edited no longer exists.
local function redraw(thread_id, focus_id, focus_index, reply_text)
  local bufnr = state.get_thread_bufnr()
  if bufnr == -1 or vim.fn.bufexists(bufnr) == 0 then return end
  if vim.b[bufnr].gh_review_thread_id ~= thread_id then return end

  local t = state.get_thread(thread_id)
  local comments = state.get(state.get(t or {}, "comments", {}), "nodes", {})
  if #comments == 0 then
    M.close_thread_buffer()
    print("Thread no longer exists")
    return
  end

  reply_text = reply_text or get_reply_text(bufnr, vim.b[bufnr].gh_review_reply_start or -1)
  if editing and not vim.iter(comments):any(function(c) return c.id == editing.id end) then
    editing = nil
    reply_text = ""
  end
  render(bufnr, t, reply_text)

  local target
  for i, r in ipairs(comment_ranges) do
    if r.comment.id == focus_id then target = r break end
    if i == focus_index then target = r end
  end
  target = target or comment_ranges[#comment_ranges]
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    vim.api.nvim_win_set_cursor(winid, { target.first, 0 })
  end
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
    api_mod.graphql(graphql.MUTATION_ADD_REVIEW_COMMENT, inner_vars, function(_, comment_err)
      if comment_err then return end
      local submit_vars = { reviewId = review_id, event = "COMMENT" }
      api_mod.graphql(graphql.MUTATION_SUBMIT_REVIEW, submit_vars, function(_, submit_err)
        if submit_err then return end
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

local function submit_edit(body, bufnr)
  if body == "" then
    local key = config.options.keymaps.thread.delete
    local hint = type(key) == "string" and ("; use " .. key_hint(key) .. " to delete it") or ""
    vim.notify("[gh-review] Comment body is empty" .. hint, vim.log.levels.WARN)
    return
  end
  if body == normalize_body(editing.body) then
    print("No changes")
    return
  end

  local thread_id = vim.b[bufnr].gh_review_thread_id
  local comment_id = editing.id
  local vars = { pullRequestReviewCommentId = comment_id, body = body }
  print("Saving comment...")
  api_mod.graphql(graphql.MUTATION_UPDATE_COMMENT, vars, function(_, err)
    if err then return end
    -- Saved, but stay in edit mode until the redraw: if the refresh fails the
    -- buffer still says "Editing", and saving again is then a no-op.
    if editing and editing.id == comment_id then editing.body = body end
    print("Comment saved")
    require("gh_review").refresh_threads(function()
      editing = nil
      redraw(thread_id, comment_id, nil, "")
    end)
  end)
end

local function submit_reply()
  local bufnr = state.get_thread_bufnr()
  if bufnr == -1 then return end
  local reply_start = vim.b[bufnr].gh_review_reply_start or -1
  local body = get_reply_text(bufnr, reply_start)
  if editing then
    submit_edit(body, bufnr)
    return
  end
  if body == "" then
    print("No reply text to submit")
    return
  end

  if vim.b[bufnr].gh_review_is_new then
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

-- The comment whose rendered lines contain the cursor, and its position.
local function comment_at_cursor()
  local lnum = vim.fn.line(".")
  for i, r in ipairs(comment_ranges) do
    if lnum >= r.first and lnum <= r.last then return r.comment, i end
  end
  return nil
end

local function author_of(comment)
  return state.get(state.get(comment, "author", {}), "login", "unknown")
end

-- Run `fn` once text below the separator may be thrown away: right away when
-- nothing would be lost, otherwise after the user agrees.
local function confirm_discard(bufnr, fn)
  local text = get_reply_text(bufnr, vim.b[bufnr].gh_review_reply_start or -1)
  local unchanged_edit = editing and text == normalize_body(editing.body)
  if text == "" or unchanged_edit then
    fn()
    return
  end
  vim.ui.select({ "Yes", "No" }, { prompt = "Discard the text below the separator?" }, function(choice)
    if choice == "Yes" then fn() end
  end)
end

local function edit_comment()
  local bufnr = state.get_thread_bufnr()
  if bufnr == -1 then return end
  local comment = comment_at_cursor()
  if not comment then
    print("No comment under the cursor")
    return
  end
  if state.get(comment, "viewerCanUpdate", false) ~= true then
    vim.notify("[gh-review] You can't edit this comment", vim.log.levels.WARN)
    return
  end

  confirm_discard(bufnr, function()
    local body = state.get(comment, "body", "")
    editing = { id = comment.id, body = body, author = author_of(comment) }
    local reply_start = render(bufnr, state.get_thread(vim.b[bufnr].gh_review_thread_id), normalize_body(body))
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.api.nvim_win_set_cursor(winid, { math.min(reply_start + 1, vim.api.nvim_buf_line_count(bufnr)), 0 })
    end
  end)
end

local function delete_comment()
  local bufnr = state.get_thread_bufnr()
  if bufnr == -1 then return end
  local comment, index = comment_at_cursor()
  if not comment then
    print("No comment under the cursor")
    return
  end
  if state.get(comment, "viewerCanDelete", false) ~= true then
    vim.notify("[gh-review] You can't delete this comment", vim.log.levels.WARN)
    return
  end

  local thread_id = vim.b[bufnr].gh_review_thread_id
  local prompt = string.format("Delete %s's comment?", author_of(comment))
  if editing and editing.id == comment.id
      and get_reply_text(bufnr, vim.b[bufnr].gh_review_reply_start or -1) ~= normalize_body(editing.body) then
    prompt = string.format("Delete %s's comment? You have unsaved edits to it.", author_of(comment))
  end
  vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
    if choice ~= "Yes" then return end
    print("Deleting comment...")
    api_mod.graphql(graphql.MUTATION_DELETE_COMMENT, { id = comment.id }, function(_, err)
      if err then return end
      print("Comment deleted")
      require("gh_review").refresh_threads(function()
        redraw(thread_id, nil, index)
      end)
    end)
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

-- Action declaration for the thread buffer. `submit` and `close_insert` each
-- own two mappings with different handlers: the insert-mode variants leave
-- insert mode first. M.close_thread_buffer is referenced through a closure
-- because it is defined further down the module.
local ACTIONS = {
  submit = {
    { "n", submit_reply, "Submit reply" },
    { "i", function() vim.cmd("stopinsert") submit_reply() end, "Submit reply" },
  },
  resolve = { { "n", toggle_resolve, "Toggle resolved" } },
  edit    = { { "n", edit_comment, "Edit comment under cursor" } },
  delete  = { { "n", delete_comment, "Delete comment under cursor" } },
  close   = { { "n", function() M.close_thread_buffer() end, "Close thread" } },
  close_insert = {
    { "n", function() M.close_thread_buffer() end, "Close thread" },
    { "i", function() vim.cmd("stopinsert") M.close_thread_buffer() end, "Close thread" },
  },
}

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

  local line_num = state.get(t, "line", nil)
  if not line_num or (type(line_num) == "number" and line_num <= 0) then
    line_num = state.get(t, "originalLine", 0)
  end
  local initial_body = state.get(t, "_initial_body", "")

  -- Create buffer in a horizontal split below the current window. :split
  -- rather than :new, which would strand the empty buffer it creates.
  vim.cmd("botright split")
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

  local reply_start = render(bufnr, t, initial_body)

  -- Only needed when creating a thread; render() keeps the rest current.
  vim.b[bufnr].gh_review_line = line_num
  vim.b[bufnr].gh_review_start_line = state.get(t, "startLine", vim.NIL)
  vim.b[bufnr].gh_review_side = state.get(t, "diffSide", "RIGHT")

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
  config.apply_keymaps(bufnr, "thread", ACTIONS)

  -- Set omnifunc for @-mention completion
  vim.bo[bufnr].omnifunc = "v:lua.require'gh_review.thread'.omnifunc"

  -- Position cursor at the reply area
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  if initial_body ~= "" then
    local target = math.min(reply_start + 2, total_lines)
    vim.api.nvim_win_set_cursor(0, { target, 0 })
  else
    vim.api.nvim_win_set_cursor(0, { math.min(reply_start, total_lines), 0 })
    if state.get(t, "id", "") == "" then
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
      win.close_current()
    end
    if vim.fn.bufexists(bufnr) == 1 then
      vim.cmd("silent! bwipeout! " .. bufnr)
    end
  end
  state.set_thread_bufnr(-1)
  state.set_thread_winid(-1)
  editing = nil

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
