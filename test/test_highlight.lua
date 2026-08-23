-- Tests for highlighting consistency between the two diff panes.

local h = require("test.helpers")
local diff = require("gh_review.diff")

local SAMPLE = "/tmp/gh_review_hl_sample.lua"
local LINES = { "local M = {}", "-- a comment", "function M.f(x)", "  return x", "end", "return M" }

-- The treesitter language highlighting a buffer, or nil when it is on regex syntax.
local function ts_lang(buf)
  if vim.treesitter.highlighter.active[buf] == nil then return nil end
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then return nil end
  return parser:lang()
end

-- Every highlight group reported at a position, from whichever engine supplied it.
local function groups_at(buf, row, col)
  local info = vim.inspect_pos(buf, row, col)
  local out = {}
  for _, c in ipairs(info.treesitter or {}) do out[#out + 1] = "@" .. c.capture end
  for _, s in ipairs(info.syntax or {}) do out[#out + 1] = s.hl_group_link or s.hl_group end
  table.sort(out)
  return table.concat(out, ",")
end

local function head_pane()
  vim.fn.writefile(LINES, SAMPLE)
  vim.cmd("edit " .. vim.fn.fnameescape(SAMPLE))
  return vim.api.nvim_get_current_buf()
end

local function base_pane()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  vim.api.nvim_buf_call(buf, function() vim.cmd("setlocal syntax=lua") end)
  return buf
end

local function cleanup(left, right)
  vim.fn.delete(SAMPLE)
  pcall(vim.api.nvim_buf_delete, left, { force = true })
  pcall(vim.api.nvim_buf_delete, right, { force = true })
end

h.run_test("Highlighting: base pane adopts the head pane's engine on a local checkout", function()
  local right = head_pane()
  local left = base_pane()

  h.assert_equal("lua", ts_lang(right), "head pane got treesitter from :edit")
  h.assert_true(ts_lang(left) == nil, "base pane starts on regex syntax only")

  diff.sync_highlighting(left, right)

  h.assert_equal("lua", ts_lang(left), "base pane switched to the same engine")
  h.assert_equal(ts_lang(right), ts_lang(left), "both panes agree on the language")

  cleanup(left, right)
end)

h.run_test("Highlighting: identical source lines report identical groups", function()
  local right = head_pane()
  local left = base_pane()
  diff.sync_highlighting(left, right)

  -- Force a parse so captures are materialised in headless.
  for _, b in ipairs({ left, right }) do
    local ok, p = pcall(vim.treesitter.get_parser, b)
    if ok and p then p:parse(true) end
  end

  local checked, mismatched = 0, {}
  for row = 0, #LINES - 1 do
    for col = 0, #LINES[row + 1] - 1 do
      local l, r = groups_at(left, row, col), groups_at(right, row, col)
      checked = checked + 1
      if l ~= r then
        mismatched[#mismatched + 1] = string.format("row %d col %d: base=%q head=%q", row, col, l, r)
      end
    end
  end

  h.assert_true(checked > 0, "should have compared some positions")
  h.assert_equal(0, #mismatched,
    "panes must highlight identical text identically; first mismatch: " .. (mismatched[1] or ""))

  cleanup(left, right)
end)

h.run_test("Highlighting: no-checkout panes are left alone", function()
  -- Both panes are scratch buffers here, so neither has treesitter and there is
  -- nothing to mirror. sync_highlighting must not introduce an asymmetry.
  local left, right = base_pane(), base_pane()

  diff.sync_highlighting(left, right)

  h.assert_true(ts_lang(left) == nil, "base pane untouched")
  h.assert_true(ts_lang(right) == nil, "head pane untouched")
  h.assert_equal("lua", vim.bo[left].syntax, "regex syntax preserved")

  cleanup(left, right)
end)

h.run_test("Highlighting: tolerates invalid buffers", function()
  local right = head_pane()
  local left = base_pane()
  vim.api.nvim_buf_delete(left, { force = true })
  diff.sync_highlighting(left, right)  -- must not error
  pcall(vim.api.nvim_buf_delete, right, { force = true })
  vim.fn.delete(SAMPLE)
end)

h.write_results("/tmp/gh_review_test_highlight.txt")
