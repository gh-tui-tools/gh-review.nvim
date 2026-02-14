-- Side-by-side diff view with review thread signs.

local state = require("gh_review.state")
local api_mod = require("gh_review.api")

local M = {}

-- Get the effective line number for a thread, falling back to originalLine
-- for outdated threads where line is null.
local function get_thread_line(t)
  local raw = state.get(t, "line", nil)
  if raw and type(raw) == "number" and raw > 0 then
    return raw
  end
  local orig = state.get(t, "originalLine", nil)
  if orig and type(orig) == "number" and orig > 0 then
    return orig
  end
  return 0
end

-- Remove a trailing empty string from split output.
local function trim_trailing_empty(lines)
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end
end

local function get_current_side()
  if vim.api.nvim_get_current_buf() == state.get_left_bufnr() then
    return "LEFT"
  end
  return "RIGHT"
end

local function place_signs(path)
  local file_threads = state.get_threads_for_file(path)
  local lbuf = state.get_left_bufnr()
  local rbuf = state.get_right_bufnr()

  -- Clear existing extmarks
  if lbuf ~= -1 and vim.fn.bufexists(lbuf) == 1 then
    vim.api.nvim_buf_clear_namespace(lbuf, state.ns, 0, -1)
  end
  if rbuf ~= -1 and vim.fn.bufexists(rbuf) == 1 then
    vim.api.nvim_buf_clear_namespace(rbuf, state.ns, 0, -1)
  end

  for _, t in ipairs(file_threads) do
    local line = get_thread_line(t)
    if line > 0 then
      local side = state.get(t, "diffSide", "RIGHT")
      local target_bufnr = side == "LEFT" and lbuf or rbuf
      if target_bufnr ~= -1 and vim.fn.bufexists(target_bufnr) == 1 then
        local line_count = vim.api.nvim_buf_line_count(target_bufnr)
        if line > line_count then goto continue end

        local is_resolved = state.get(t, "isResolved", false)
        local is_pending = false
        local comments_obj = state.get(t, "comments", {})
        local comments = state.get(comments_obj, "nodes", {})
        if #comments > 0 then
          local last_comment = comments[#comments]
          local review = state.get(last_comment, "pullRequestReview", {})
          if type(review) == "table" and next(review) and state.get(review, "state", "") == "PENDING" then
            is_pending = true
          end
        end

        local sign_text = "CT"
        local sign_hl = "GHReviewThread"
        if is_pending then
          sign_text = "CP"
          sign_hl = "GHReviewThreadPending"
        elseif is_resolved then
          sign_text = "CR"
          sign_hl = "GHReviewThreadResolved"
        end

        -- Build virtual text label from first comment
        local virt_text
        if #comments > 0 then
          local first = comments[1]
          local author_obj = state.get(first, "author", {})
          local author = state.get(author_obj, "login", "")
          local body = state.get(first, "body", "")
          body = body:gsub("\r", ""):gsub("\n", " "):gsub("%s+", " ")
          if #body > 60 then
            body = body:sub(1, 57) .. "..."
          end
          if author ~= "" and body ~= "" then
            virt_text = {{ author .. ": " .. body, "GHReviewVirtText" }}
          end
        end

        vim.api.nvim_buf_set_extmark(target_bufnr, state.ns, line - 1, 0, {
          sign_text = sign_text,
          sign_hl_group = sign_hl,
          virt_text = virt_text,
          virt_text_pos = "eol",
        })
      end
    end
    ::continue::
  end
end

function M.refresh_signs()
  local path = state.get_diff_path()
  if path ~= "" then
    place_signs(path)
  end
end

-- Module-local state for floating preview window
local preview_winid = -1
local preview_bufnr = -1

local function close_preview()
  if preview_winid ~= -1 and vim.api.nvim_win_is_valid(preview_winid) then
    vim.api.nvim_win_close(preview_winid, true)
  end
  if preview_bufnr ~= -1 and vim.fn.bufexists(preview_bufnr) == 1 then
    vim.cmd("silent! bwipeout! " .. preview_bufnr)
  end
  preview_winid = -1
  preview_bufnr = -1
end

local function preview_thread_at_cursor()
  close_preview()

  local lnum = vim.fn.line(".")
  local side = get_current_side()
  local path = state.get_diff_path()
  local file_threads = state.get_threads_for_file(path)

  local t
  for _, thread in ipairs(file_threads) do
    local thread_line = get_thread_line(thread)
    if thread_line > 0 then
      local thread_side = state.get(thread, "diffSide", "RIGHT")
      if thread_line == lnum and thread_side == side then
        t = thread
        break
      end
    end
  end

  if not t then
    print("No thread at this line")
    return
  end

  local comments_obj = state.get(t, "comments", {})
  local comments = state.get(comments_obj, "nodes", {})
  if #comments == 0 then
    print("No comments in this thread")
    return
  end

  -- Build content lines
  local lines = {}
  local is_resolved = state.get(t, "isResolved", false)
  lines[#lines + 1] = is_resolved and "Thread [Resolved]" or "Thread [Active]"
  lines[#lines + 1] = string.rep("─", 40)

  for _, c in ipairs(comments) do
    local author_obj = state.get(c, "author", {})
    local author = state.get(author_obj, "login", "unknown")
    local created = (state.get(c, "createdAt", "")):gsub("T.*", "")
    lines[#lines + 1] = string.format("%s (%s):", author, created)
    local body = state.get(c, "body", "")
    body = body:gsub("\r", "")
    local body_lines = vim.split(body, "\n", { plain = true })
    for _, bl in ipairs(body_lines) do
      lines[#lines + 1] = "  " .. bl
    end
    lines[#lines + 1] = ""
  end

  -- Remove trailing blank line
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end

  -- Calculate dimensions
  local max_width = 0
  for _, l in ipairs(lines) do
    if #l > max_width then max_width = #l end
  end
  max_width = math.min(math.max(max_width + 2, 30), 80)
  local height = math.min(#lines, 20)

  -- Create buffer and window
  preview_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(preview_bufnr, 0, -1, false, lines)
  vim.bo[preview_bufnr].buftype = "nofile"
  vim.bo[preview_bufnr].modifiable = false
  vim.bo[preview_bufnr].filetype = "gh-review-thread"

  preview_winid = vim.api.nvim_open_win(preview_bufnr, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = max_width,
    height = height,
    border = "rounded",
    style = "minimal",
  })

  -- Close on q, Esc, or BufLeave
  local opts = { buffer = preview_bufnr, silent = true }
  vim.keymap.set("n", "q", close_preview, opts)
  vim.keymap.set("n", "<Esc>", close_preview, opts)
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = preview_bufnr,
    once = true,
    callback = close_preview,
  })
end

local function open_thread_at_cursor()
  local lnum = vim.fn.line(".")
  local side = get_current_side()
  local path = state.get_diff_path()
  local file_threads = state.get_threads_for_file(path)

  for _, t in ipairs(file_threads) do
    local thread_line = get_thread_line(t)
    if thread_line > 0 then
      local thread_side = state.get(t, "diffSide", "RIGHT")
      if thread_line == lnum and thread_side == side then
        require("gh_review.thread").open(t.id)
        return
      end
    end
  end

  print("No thread at this line")
end

local function create_comment_at_cursor()
  local lnum = vim.fn.line(".")
  local side = get_current_side()
  local path = state.get_diff_path()
  require("gh_review.thread").open_new(path, lnum, lnum, side)
end

local function create_comment_visual()
  local start_lnum = math.min(vim.fn.line("v"), vim.fn.line("."))
  local end_lnum = math.max(vim.fn.line("v"), vim.fn.line("."))
  local side = get_current_side()
  local path = state.get_diff_path()
  require("gh_review.thread").open_new(path, start_lnum, end_lnum, side)
end

local function create_suggestion_at_cursor()
  if get_current_side() ~= "RIGHT" then
    print("Suggestions are only available in the head (right) buffer")
    return
  end
  local lnum = vim.fn.line(".")
  local path = state.get_diff_path()
  local code_line = vim.fn.getline(lnum)
  local suggestion = "```suggestion\n" .. code_line .. "\n```"
  require("gh_review.thread").open_new(path, lnum, lnum, "RIGHT", suggestion)
end

local function create_suggestion_visual()
  if get_current_side() ~= "RIGHT" then
    print("Suggestions are only available in the head (right) buffer")
    return
  end
  local start_lnum = math.min(vim.fn.line("v"), vim.fn.line("."))
  local end_lnum = math.max(vim.fn.line("v"), vim.fn.line("."))
  local path = state.get_diff_path()
  local buf_lines = vim.api.nvim_buf_get_lines(0, start_lnum - 1, end_lnum, false)
  local suggestion = "```suggestion\n" .. table.concat(buf_lines, "\n") .. "\n```"
  require("gh_review.thread").open_new(path, start_lnum, end_lnum, "RIGHT", suggestion)
end

local function jump_to_next_thread()
  local lnum = vim.fn.line(".")
  local side = get_current_side()
  local path = state.get_diff_path()
  local file_threads = state.get_threads_for_file(path)

  local next_line = 999999
  for _, t in ipairs(file_threads) do
    local thread_line = get_thread_line(t)
    if thread_line > 0 then
      local thread_side = state.get(t, "diffSide", "RIGHT")
      if thread_side == side and thread_line > lnum and thread_line < next_line then
        next_line = thread_line
      end
    end
  end

  if next_line < 999999 then
    vim.api.nvim_win_set_cursor(0, { next_line, 0 })
  else
    print("No more threads")
  end
end

local function jump_to_prev_thread()
  local lnum = vim.fn.line(".")
  local side = get_current_side()
  local path = state.get_diff_path()
  local file_threads = state.get_threads_for_file(path)

  local prev_line = 0
  for _, t in ipairs(file_threads) do
    local thread_line = get_thread_line(t)
    if thread_line > 0 then
      local thread_side = state.get(t, "diffSide", "RIGHT")
      if thread_side == side and thread_line < lnum and thread_line > prev_line then
        prev_line = thread_line
      end
    end
  end

  if prev_line > 0 then
    vim.api.nvim_win_set_cursor(0, { prev_line, 0 })
  else
    print("No more threads")
  end
end

local function write_buffer(bufnr, path)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.fn.writefile(lines, path)
  vim.bo[bufnr].modified = false
  vim.b[bufnr].gh_review_file_mtime = vim.fn.getftime(path)
  local size = vim.fn.getfsize(path)
  print(string.format('"%s" %dL, %dB written', path, #lines, size))
end

local function check_external_change(bufnr)
  local path = vim.b[bufnr].gh_review_file_path
  if not path or path == "" then return end
  local old_mtime = vim.b[bufnr].gh_review_file_mtime or 0
  local cur_mtime = vim.fn.getftime(path)
  if cur_mtime <= old_mtime then return end
  vim.b[bufnr].gh_review_file_mtime = cur_mtime
  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("%s changed on disk. Reload?", path),
  }, function(choice)
    if choice ~= "Yes" then return end
    local new_content = vim.fn.readfile(path)
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.fn.win_gotoid(winid)
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_content)
    vim.bo[bufnr].modified = false
    vim.cmd("diffupdate")
    vim.cmd("redraw")
    print("Reloaded from disk")
  end)
end

local syntax_map = {
  ts = "typescript",
  tsx = "typescriptreact",
  js = "javascript",
  jsx = "javascriptreact",
  py = "python",
  rb = "ruby",
  rs = "rust",
  go = "go",
  java = "java",
  kt = "kotlin",
  kts = "kotlin",
  swift = "swift",
  php = "php",
  lua = "lua",
  pl = "perl",
  pm = "perl",
  sh = "sh",
  bash = "sh",
  zsh = "zsh",
  vim = "vim",
  el = "lisp",
  ex = "elixir",
  exs = "elixir",
  erl = "erlang",
  hs = "haskell",
  scala = "scala",
  r = "r",
  yml = "yaml",
  md = "markdown",
  h = "c",
  hpp = "cpp",
  cc = "cpp",
  cxx = "cpp",
  cs = "cs",
  m = "objc",
  mm = "objcpp",
}

local function setup_diff_buffer(bufnr, name, path, content, editable)
  if editable then
    vim.bo[bufnr].buftype = "acwrite"
  else
    vim.bo[bufnr].buftype = "nofile"
  end
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
  if editable then
    vim.bo[bufnr].modified = false
    vim.b[bufnr].gh_review_file_path = path
    vim.b[bufnr].gh_review_file_mtime = vim.fn.getftime(path)
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = bufnr,
      callback = function() write_buffer(bufnr, path) end,
    })
    vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
      buffer = bufnr,
      callback = function() check_external_change(bufnr) end,
    })
  else
    vim.bo[bufnr].modifiable = false
  end

  -- Set syntax highlighting from path extension.
  local ext = vim.fn.fnamemodify(path, ":e")
  if ext and ext ~= "" then
    local syn = syntax_map[ext] or ext
    vim.cmd("setlocal syntax=" .. syn)
  end

  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    vim.wo[winid].foldmethod = "diff"
    vim.wo[winid].signcolumn = "yes"
    vim.wo[winid].number = false
  end

  -- Mark buffer so the fold guard can identify it
  vim.b[bufnr].gh_review_diff = true

  -- Diff-buffer-local keymaps
  vim.keymap.set("n", "gt", open_thread_at_cursor, { buffer = bufnr, silent = true, desc = "Open review thread" })
  vim.keymap.set("n", "gc", create_comment_at_cursor, { buffer = bufnr, silent = true, desc = "New comment" })
  vim.keymap.set("x", "gc", create_comment_visual, { buffer = bufnr, silent = true, desc = "New comment (range)" })
  vim.keymap.set("n", "]t", jump_to_next_thread, { buffer = bufnr, silent = true, desc = "Next review thread" })
  vim.keymap.set("n", "[t", jump_to_prev_thread, { buffer = bufnr, silent = true, desc = "Previous review thread" })
  vim.keymap.set("n", "gs", create_suggestion_at_cursor, { buffer = bufnr, silent = true, desc = "New suggestion" })
  vim.keymap.set("x", "gs", create_suggestion_visual, { buffer = bufnr, silent = true, desc = "New suggestion (range)" })
  vim.keymap.set("n", "gf", function() require("gh_review.files").toggle() end, { buffer = bufnr, silent = true, desc = "Toggle files list" })
  vim.keymap.set("n", "q", function() M.close_diff() end, { buffer = bufnr, silent = true, desc = "Close diff" })
  vim.keymap.set("n", "K", preview_thread_at_cursor, { buffer = bufnr, silent = true, desc = "Preview thread" })
end

local function show_diff(path, left_content, right_content)
  local left_name = "gh-review://LEFT/" .. path
  local right_name = "gh-review://RIGHT/" .. path

  -- Clean up existing left diff window
  local old_left = state.get_left_bufnr()
  if old_left ~= -1 and vim.fn.bufexists(old_left) == 1 then
    local winid = vim.fn.bufwinid(old_left)
    if winid ~= -1 then
      vim.fn.win_gotoid(winid)
      vim.cmd("close")
    end
  end

  -- Find target window: reuse existing right, or go above files list
  local old_right = state.get_right_bufnr()
  if old_right ~= -1 and vim.fn.bufexists(old_right) == 1 and vim.fn.bufwinid(old_right) ~= -1 then
    vim.fn.win_gotoid(vim.fn.bufwinid(old_right))
    vim.cmd("diffoff")
  else
    local fb = state.get_files_bufnr()
    local files_winid = fb ~= -1 and vim.fn.bufwinid(fb) or -1
    if files_winid ~= -1 then
      vim.fn.win_gotoid(files_winid)
      vim.cmd("wincmd k")
      -- If we didn't move, files is the only window -- split above it
      if vim.fn.win_getid() == files_winid then
        vim.cmd("aboveleft new")
      end
    end
  end

  -- Set up the right (head) buffer.
  local right_bufnr = vim.fn.bufnr(right_name, true)
  vim.cmd("noautocmd buffer " .. right_bufnr)
  state.set_right_bufnr(right_bufnr)
  setup_diff_buffer(right_bufnr, right_name, path, right_content, state.is_local_checkout())

  -- Set up the left (base) buffer in a vertical split
  vim.cmd("noautocmd aboveleft vnew")
  local left_bufnr = vim.fn.bufnr(left_name, true)
  vim.cmd("noautocmd buffer " .. left_bufnr)
  state.set_left_bufnr(left_bufnr)
  setup_diff_buffer(left_bufnr, left_name, path, left_content)

  -- Enable diff mode on both -- left window first, then right
  vim.cmd("wincmd p")
  vim.cmd("diffthis")
  vim.wo.wrap = true
  vim.wo.foldlevel = 0
  vim.cmd("wincmd p")
  vim.cmd("diffthis")
  vim.wo.wrap = true
  vim.wo.foldlevel = 0

  -- Set winbar on both diff windows
  local pr_num = state.get_pr_number()
  local base_short = state.get_merge_base_oid()
  if base_short == "" then base_short = state.get_base_oid() end
  base_short = base_short:sub(1, 7)
  local head_short = state.get_head_oid():sub(1, 7)
  local left_winid = vim.fn.bufwinid(left_bufnr)
  local right_winid = vim.fn.bufwinid(right_bufnr)
  if left_winid ~= -1 then
    vim.wo[left_winid].winbar = string.format(" PR #%d · %s · base (%s)", pr_num, path, base_short)
  end
  if right_winid ~= -1 then
    vim.wo[right_winid].winbar = string.format(" PR #%d · %s · head (%s)", pr_num, path, head_short)
  end

  -- Place signs for review threads
  place_signs(path)

  -- Position cursor in the right (head) window at the top
  vim.fn.win_gotoid(vim.fn.bufwinid(right_bufnr))
  vim.cmd("normal! gg")
end

local function fetch_graphql_content(ref, path, callback)
  local graphql = require("gh_review.graphql")
  local owner = state.get_owner()
  local name = state.get_name()
  local query = [[
    query($owner: String!, $name: String!, $expression: String!) {
      repository(owner: $owner, name: $name) {
        object(expression: $expression) {
          ... on Blob {
            text
          }
        }
      }
    }
  ]]
  local gql_vars = {
    owner = owner,
    name = name,
    expression = ref .. ":" .. path,
  }
  api_mod.graphql(query, gql_vars, function(result)
    local data = state.get(result, "data", {})
    local repo = type(data) == "table" and state.get(data, "repository", {}) or {}
    local obj = type(repo) == "table" and state.get(repo, "object", {}) or {}
    local text = type(obj) == "table" and state.get(obj, "text", "") or ""
    local content = vim.split(text, "\n", { plain = true, trimempty = false })
    trim_trailing_empty(content)
    callback(content)
  end)
end

local function fetch_git_content(ref, path, callback)
  local cmd = string.format("git show %s:%s",
    vim.fn.shellescape(ref), vim.fn.shellescape(path))
  vim.system({ "bash", "-c", cmd }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        -- Fall back to GraphQL blob query
        fetch_graphql_content(ref, path, callback)
        return
      end
      local content = vim.split(obj.stdout or "", "\n", { plain = true, trimempty = false })
      trim_trailing_empty(content)
      callback(content)
    end)
  end)
end

local function fetch_contents(base_oid, head_oid, path)
  -- Determine change type for this file
  local change_type = "MODIFIED"
  for _, f in ipairs(state.get_changed_files()) do
    if f.path == path then
      change_type = state.get(f, "changeType", "MODIFIED")
      break
    end
  end

  local left_content = {}
  local right_content = {}
  local fetches_done = 0
  local total_fetches = 2

  local function handle_done()
    fetches_done = fetches_done + 1
    if fetches_done >= total_fetches then
      vim.schedule(function()
        show_diff(path, left_content, right_content)
      end)
    end
  end

  -- Fetch left (base) content
  if change_type == "ADDED" then
    left_content = {}
    fetches_done = fetches_done + 1
  else
    fetch_git_content(base_oid, path, function(content)
      left_content = content
      handle_done()
    end)
  end

  -- Fetch right (head) content
  if change_type == "DELETED" then
    right_content = {}
    fetches_done = fetches_done + 1
  else
    fetch_git_content(head_oid, path, function(content)
      right_content = content
      handle_done()
    end)
  end

  -- Check if both were synchronous (ADDED/DELETED)
  if fetches_done >= total_fetches then
    vim.schedule(function()
      show_diff(path, left_content, right_content)
    end)
  end
end

function M.open(path)
  state.set_diff_path(path)

  local base_oid = state.get_merge_base_oid()
  if base_oid == "" then
    base_oid = state.get_base_oid()
  end
  local head_oid = state.get_head_oid()

  fetch_contents(base_oid, head_oid, path)
end

function M.close_diff()
  local left = state.get_left_bufnr()
  local right = state.get_right_bufnr()

  -- Clear guard flags before closing so the fold guard doesn't interfere
  if left ~= -1 and vim.fn.bufexists(left) == 1 then
    vim.b[left].gh_review_diff = false
  end
  if right ~= -1 and vim.fn.bufexists(right) == 1 then
    vim.b[right].gh_review_diff = false
  end

  -- Close the left diff window
  if left ~= -1 and vim.fn.bufexists(left) == 1 then
    local winid = vim.fn.bufwinid(left)
    if winid ~= -1 then
      vim.fn.win_gotoid(winid)
      vim.cmd("close")
    end
  end

  -- Replace right diff buffer with an empty buffer
  if right ~= -1 and vim.fn.bufexists(right) == 1 then
    local winid = vim.fn.bufwinid(right)
    if winid ~= -1 then
      vim.fn.win_gotoid(winid)
      vim.cmd("diffoff")
      vim.cmd("enew")
    end
  end

  state.set_left_bufnr(-1)
  state.set_right_bufnr(-1)
  state.set_diff_path("")

  -- Return focus to the files list
  local fb = state.get_files_bufnr()
  local files_winid = fb ~= -1 and vim.fn.bufwinid(fb) or -1
  if files_winid ~= -1 then
    vim.fn.win_gotoid(files_winid)
  end
end

return M
