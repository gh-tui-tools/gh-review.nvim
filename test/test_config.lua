-- Tests for configuration: defaults, merging, validation.

local h = require("test.helpers")
local config = require("gh_review.config")

-- Capture vim.notify output while running fn.
local function capture_notify(fn)
  local original = vim.notify
  local messages = {}
  vim.notify = function(msg) messages[#messages + 1] = msg end
  local ok, err = pcall(fn)
  vim.notify = original
  if not ok then error(err, 0) end
  return messages
end

h.run_test("Config: defaults are present and correctly shaped", function()
  config.reset()
  h.assert_true(config.options.fold.enabled, "fold enabled by default")
  h.assert_equal(0, config.options.fold.level, "fold level 0 by default")
  h.assert_equal("gt", config.options.keymaps.diff.thread_open)
  h.assert_equal("K", config.options.keymaps.diff.preview)
  h.assert_equal("<CR>", config.options.keymaps.files.open)
  h.assert_equal("<Space>", config.options.keymaps.files.toggle_viewed)
  h.assert_equal("<C-s>", config.options.keymaps.thread.submit)
  h.assert_equal("<C-q>", config.options.keymaps.thread.close_insert)
  h.assert_equal("ge", config.options.keymaps.thread.edit)
  h.assert_equal("gD", config.options.keymaps.thread.delete)
end)

h.run_test("Config: thread edit and delete accept a key or false", function()
  config.reset()
  local msgs = capture_notify(function()
    config.setup({ keymaps = { thread = { edit = "<leader>e", delete = false } } })
  end)
  h.assert_equal(0, #msgs, "no validation warnings")
  h.assert_equal("<leader>e", config.options.keymaps.thread.edit)
  h.assert_false(config.options.keymaps.thread.delete)
  config.reset()
end)

h.run_test("Config: partial override preserves untouched defaults", function()
  config.reset()
  config.setup({ keymaps = { diff = { thread_open = "<leader>gt" } } })
  h.assert_equal("<leader>gt", config.options.keymaps.diff.thread_open, "overridden")
  h.assert_equal("gc", config.options.keymaps.diff.comment, "sibling default kept")
  h.assert_equal("<CR>", config.options.keymaps.files.open, "other surface kept")
  h.assert_true(config.options.fold.enabled, "fold defaults kept")
  config.reset()
end)

h.run_test("Config: false disables a single mapping", function()
  config.reset()
  config.setup({ keymaps = { diff = { preview = false } } })
  h.assert_false(config.options.keymaps.diff.preview, "preview disabled")
  h.assert_equal("gt", config.options.keymaps.diff.thread_open, "siblings intact")
  config.reset()
end)

h.run_test("Config: fold = false normalizes to enabled = false", function()
  config.reset()
  config.setup({ fold = false })
  h.assert_false(config.options.fold.enabled, "fold disabled via shorthand")
  h.assert_equal(0, config.options.fold.level, "level still filled from defaults")
  config.reset()
end)

h.run_test("Config: fold level is configurable", function()
  config.reset()
  config.setup({ fold = { level = 99 } })
  h.assert_true(config.options.fold.enabled, "enabled stays true")
  h.assert_equal(99, config.options.fold.level, "level overridden")
  config.reset()
end)

h.run_test("Config: unknown surface warns and leaves config unchanged", function()
  config.reset()
  local msgs = capture_notify(function()
    config.setup({ keymaps = { difff = { thread_open = "x" } } })
  end)
  h.assert_true(#msgs > 0, "should warn")
  h.assert_match("difff", msgs[1], "warning names the offending surface")
  h.assert_equal("gt", config.options.keymaps.diff.thread_open, "config unchanged")
  config.reset()
end)

h.run_test("Config: unknown action warns and leaves config unchanged", function()
  config.reset()
  local msgs = capture_notify(function()
    config.setup({ keymaps = { diff = { thread = "x", preview = false } } })
  end)
  h.assert_true(#msgs > 0, "should warn")
  h.assert_match("thread", msgs[1], "warning names the offending action")
  h.assert_equal("K", config.options.keymaps.diff.preview,
    "whole call rejected, so the valid sibling is not applied either")
  config.reset()
end)

h.run_test("Config: bad value type warns and leaves config unchanged", function()
  config.reset()
  local msgs = capture_notify(function()
    config.setup({ keymaps = { diff = { thread_open = 42 } } })
  end)
  h.assert_true(#msgs > 0, "should warn")
  h.assert_equal("gt", config.options.keymaps.diff.thread_open, "config unchanged")
  config.reset()
end)

h.run_test("Config: unknown top-level key warns", function()
  config.reset()
  local msgs = capture_notify(function()
    config.setup({ keymapz = {} })
  end)
  h.assert_true(#msgs > 0, "should warn")
  h.assert_match("keymapz", msgs[1], "warning names the offending key")
  config.reset()
end)

h.run_test("Config: setup with no argument is a no-op", function()
  config.reset()
  config.setup()
  h.assert_equal("gt", config.options.keymaps.diff.thread_open)
  h.assert_true(config.options.fold.enabled)
  config.reset()
end)

h.run_test("Config: init exposes setup", function()
  config.reset()
  require("gh_review").setup({ fold = false })
  h.assert_false(config.options.fold.enabled, "init.setup delegates to config.setup")
  config.reset()
end)

-- Find a buffer-local mapping by mode and lhs. Returns the map table or nil.
local function mapped(bufnr, mode, lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
    if m.lhs == lhs then return m end
  end
  return nil
end

local function scratch()
  return vim.api.nvim_create_buf(false, true)
end

h.run_test("Keymaps: apply sets every declared mode", function()
  config.reset()
  local calls = {}
  local actions = {
    comment = {
      { "n", function() calls[#calls + 1] = "normal" end, "New comment" },
      { "x", function() calls[#calls + 1] = "visual" end, "New comment (range)" },
    },
  }
  local bufnr = scratch()
  config.setup({ keymaps = { diff = { comment = "gc" } } })
  config.apply_keymaps(bufnr, "diff", actions)

  local n = mapped(bufnr, "n", "gc")
  local x = mapped(bufnr, "x", "gc")
  h.assert_true(n ~= nil, "normal mode mapping set")
  h.assert_true(x ~= nil, "visual mode mapping set")
  h.assert_equal("New comment", n.desc, "normal desc preserved")
  h.assert_equal("New comment (range)", x.desc, "visual desc preserved")

  n.callback()
  x.callback()
  h.assert_equal("normal", calls[1], "normal mode got its own handler")
  h.assert_equal("visual", calls[2], "visual mode got a different handler")

  vim.api.nvim_buf_delete(bufnr, { force = true })
  config.reset()
end)

h.run_test("Keymaps: false drops the mapping entirely", function()
  config.reset()
  local actions = {
    preview = { { "n", function() end, "Preview thread" } },
  }
  local bufnr = scratch()
  config.setup({ keymaps = { diff = { preview = false } } })
  config.apply_keymaps(bufnr, "diff", actions)

  h.assert_true(mapped(bufnr, "n", "K") == nil, "K left free for LSP hover")

  vim.api.nvim_buf_delete(bufnr, { force = true })
  config.reset()
end)

h.run_test("Keymaps: remap applies at the new lhs and not the old", function()
  config.reset()
  local actions = {
    thread_open = { { "n", function() end, "Open review thread" } },
  }
  local bufnr = scratch()
  config.setup({ keymaps = { diff = { thread_open = "Z" } } })
  config.apply_keymaps(bufnr, "diff", actions)

  h.assert_true(mapped(bufnr, "n", "Z") ~= nil, "present at new lhs")
  h.assert_true(mapped(bufnr, "n", "gt") == nil, "absent at old lhs")

  vim.api.nvim_buf_delete(bufnr, { force = true })
  config.reset()
end)

h.run_test("Keymaps: clear removes exactly what apply set", function()
  config.reset()
  local actions = {
    comment = {
      { "n", function() end, "New comment" },
      { "x", function() end, "New comment (range)" },
    },
    thread_open = { { "n", function() end, "Open review thread" } },
    preview = { { "n", function() end, "Preview thread" } },
  }
  local bufnr = scratch()
  config.setup({ keymaps = { diff = { comment = "gc", thread_open = "Z", preview = false } } })
  config.apply_keymaps(bufnr, "diff", actions)

  h.assert_true(mapped(bufnr, "n", "gc") ~= nil, "applied before clear")
  h.assert_true(mapped(bufnr, "x", "gc") ~= nil, "applied before clear")
  h.assert_true(mapped(bufnr, "n", "Z") ~= nil, "applied before clear")

  config.clear_keymaps(bufnr, "diff", actions)

  h.assert_true(mapped(bufnr, "n", "gc") == nil, "normal mapping cleared")
  h.assert_true(mapped(bufnr, "x", "gc") == nil, "visual mapping cleared")
  h.assert_true(mapped(bufnr, "n", "Z") == nil, "remapped key cleared at its configured lhs")

  vim.api.nvim_buf_delete(bufnr, { force = true })
  config.reset()
end)

h.run_test("Keymaps: clear on a buffer with nothing applied does not error", function()
  config.reset()
  local actions = { thread_open = { { "n", function() end, "Open review thread" } } }
  local bufnr = scratch()
  config.clear_keymaps(bufnr, "diff", actions)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  config.reset()
end)

h.run_test("Folds: settings for the three configured modes", function()
  config.reset()
  local s = config.fold_settings()
  h.assert_true(s.foldenable, "default: folding on")
  h.assert_equal(0, s.foldlevel, "default: all folds closed")

  config.setup({ fold = { level = 99 } })
  s = config.fold_settings()
  h.assert_true(s.foldenable, "level override: folding still on")
  h.assert_equal(99, s.foldlevel, "level override applied")

  config.setup({ fold = false })
  s = config.fold_settings()
  h.assert_false(s.foldenable, "disabled: folding off")
  h.assert_true(s.foldlevel == nil, "disabled: foldlevel left untouched")

  config.reset()
end)

h.run_test("Folds: diffthis forces foldmethod, so foldenable is the real lever", function()
  config.reset()

  local lines = {}
  for i = 1, 40 do lines[i] = "line " .. i end
  local changed = vim.deepcopy(lines)
  changed[20] = "CHANGED"

  local function diff_pair()
    vim.cmd("tabnew")
    local left = vim.api.nvim_get_current_buf()
    vim.bo[left].buftype = "nofile"
    vim.api.nvim_buf_set_lines(left, 0, -1, false, lines)
    local lwin = vim.api.nvim_get_current_win()

    vim.cmd("vsplit")
    local right = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(right)
    vim.api.nvim_buf_set_lines(right, 0, -1, false, changed)
    local rwin = vim.api.nvim_get_current_win()

    vim.api.nvim_set_current_win(lwin); vim.cmd("diffthis")
    vim.api.nvim_set_current_win(rwin); vim.cmd("diffthis")
    return rwin
  end

  local function apply(winid, s)
    vim.wo[winid].foldenable = s.foldenable
    if s.foldlevel ~= nil then vim.wo[winid].foldlevel = s.foldlevel end
  end

  -- Default: folds closed. Line 1 is far from the change at line 20.
  local rwin = diff_pair()
  h.assert_equal("diff", vim.wo[rwin].foldmethod, "diffthis forces foldmethod=diff")
  apply(rwin, config.fold_settings())
  h.assert_true(vim.fn.foldclosed(1) ~= -1, "default: line 1 sits in a closed fold")
  vim.cmd("tabclose!")

  -- Level 99: folds exist but are open.
  config.setup({ fold = { level = 99 } })
  rwin = diff_pair()
  apply(rwin, config.fold_settings())
  h.assert_equal(-1, vim.fn.foldclosed(1), "level 99: nothing closed")
  h.assert_equal("diff", vim.wo[rwin].foldmethod, "level 99: foldmethod untouched")
  vim.cmd("tabclose!")

  -- Disabled: nothing closed, and foldmethod is still diff because we never
  -- fight :diffthis for it.
  config.setup({ fold = false })
  rwin = diff_pair()
  apply(rwin, config.fold_settings())
  h.assert_equal(-1, vim.fn.foldclosed(1), "disabled: nothing closed")
  h.assert_false(vim.wo[rwin].foldenable, "disabled: foldenable off")
  vim.cmd("tabclose!")

  config.reset()
end)

h.write_results("/tmp/gh_review_test_config.txt")
