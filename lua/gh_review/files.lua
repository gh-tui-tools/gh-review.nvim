-- Changed files list buffer.

local state = require("gh_review.state")

local M = {}

local BUF_NAME = "gh-review://files"

local function change_type_to_flag(change_type)
  if change_type == "ADDED" then return "A"
  elseif change_type == "DELETED" then return "D"
  elseif change_type == "RENAMED" then return "R"
  elseif change_type == "COPIED" then return "C"
  end
  return "M"
end

local function render()
  local files = state.get_changed_files()
  local lines = {}
  local pr_title = state.get_pr_title()
  local pr_number = state.get_pr_number()
  local pr_url = string.format("https://github.com/%s/%s/pull/%d", state.get_owner(), state.get_name(), pr_number)
  lines[#lines + 1] = string.format("%s: %s", pr_url, pr_title)
  lines[#lines + 1] = string.format("Files changed (%d)", #files)
  lines[#lines + 1] = ""

  for _, f in ipairs(files) do
    local flag = change_type_to_flag(state.get(f, "changeType", "MODIFIED"))
    local additions = state.get(f, "additions", 0)
    local deletions = state.get(f, "deletions", 0)
    local path = state.get(f, "path", "")

    local file_threads = state.get_threads_for_file(path)
    local thread_count = #file_threads
    local thread_info = ""
    if thread_count > 0 then
      thread_info = string.format("  [%d thread%s]", thread_count, thread_count > 1 and "s" or "")
    end

    lines[#lines + 1] = string.format("  +%-4d -%-4d %s  %s%s", additions, deletions, flag, path, thread_info)
  end

  local bufnr = state.get_files_bufnr()
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  -- Position cursor on first file line
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    vim.api.nvim_win_set_cursor(winid, { 4, 0 })
  end
end

local function open_file_under_cursor()
  local lnum = vim.fn.line(".")
  -- First 3 lines are header
  if lnum <= 3 then return end
  local file_idx = lnum - 3 -- 1-indexed: line 4 = file 1
  local files = state.get_changed_files()
  if file_idx < 1 or file_idx > #files then return end
  local path = files[file_idx].path
  require("gh_review.diff").open(path)
end

local function refresh_and_render()
  require("gh_review").refresh_threads()
end

local function setup_buffer()
  local bufnr = state.get_files_bufnr()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false

  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    vim.wo[winid].wrap = false
    vim.wo[winid].number = false
    vim.wo[winid].relativenumber = false
    vim.wo[winid].signcolumn = "no"
    vim.wo[winid].list = false
    vim.wo[winid].winfixheight = true
  end

  vim.bo[bufnr].filetype = "gh-review-files"

  -- Keymaps
  vim.keymap.set("n", "<CR>", open_file_under_cursor, { buffer = bufnr, silent = true, desc = "Open diff" })
  vim.keymap.set("n", "q", function() M.close() end, { buffer = bufnr, silent = true, desc = "Close files list" })
  vim.keymap.set("n", "gf", function() M.close() end, { buffer = bufnr, silent = true, desc = "Close files list" })
  vim.keymap.set("n", "R", refresh_and_render, { buffer = bufnr, silent = true, desc = "Refresh threads" })
end

function M.open()
  -- Reuse existing buffer if it exists
  local bufnr = state.get_files_bufnr()
  if bufnr ~= -1 and vim.fn.bufexists(bufnr) == 1 then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.fn.win_gotoid(winid)
      render()
      return
    end
  end

  -- Create a new split at the bottom
  vim.cmd("botright new")
  vim.cmd("resize 12")
  local new_bufnr = vim.fn.bufnr(BUF_NAME, true)
  vim.cmd("buffer " .. new_bufnr)
  state.set_files_bufnr(new_bufnr)

  setup_buffer()
  render()
end

function M.close()
  local bufnr = state.get_files_bufnr()
  if bufnr ~= -1 and vim.fn.bufexists(bufnr) == 1 then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.fn.win_gotoid(winid)
      vim.cmd("close")
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
  end
end

function M.toggle()
  local bufnr = state.get_files_bufnr()
  if bufnr ~= -1 and vim.fn.bufexists(bufnr) == 1 and vim.fn.bufwinid(bufnr) ~= -1 then
    M.close()
  else
    M.open()
  end
end

function M.rerender()
  local bufnr = state.get_files_bufnr()
  if bufnr ~= -1 and vim.fn.bufexists(bufnr) == 1 then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      local save_winid = vim.fn.win_getid()
      vim.fn.win_gotoid(winid)
      render()
      vim.fn.win_gotoid(save_winid)
    end
  end
end

return M
