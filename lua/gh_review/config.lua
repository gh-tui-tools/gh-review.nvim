-- User configuration for gh-review.nvim.
--
-- Consumers must read `M.options` at use time rather than capturing it at
-- module load: plugin/gh_review.lua is sourced before any setup() call can run.

local M = {}

M.defaults = {
  fold = { enabled = true, level = 0 },
  keymaps = {
    diff = {
      thread_open  = "gt",
      comment      = "gc",
      suggestion   = "gs",
      next_thread  = "]t",
      prev_thread  = "[t",
      preview      = "K",
      toggle_files = "gf",
      goto_file    = "gF",
      close        = "q",
    },
    files = {
      open          = "<CR>",
      toggle_viewed = "<Space>",
      refresh       = "R",
      toggle_files  = "gf",
      close         = "q",
    },
    thread = {
      submit       = "<C-s>",
      resolve      = "<C-r>",
      delete       = "gD",
      close        = "q",
      close_insert = "<C-q>",
    },
  },
}

M.options = vim.deepcopy(M.defaults)

-- Restore defaults. Used by the test suite between cases.
function M.reset()
  M.options = vim.deepcopy(M.defaults)
end

local function warn(msg)
  vim.notify("[gh-review] " .. msg, vim.log.levels.WARN)
end

local function validate_keymaps(keymaps)
  if keymaps == nil then return true end
  if type(keymaps) ~= "table" then
    warn("keymaps must be a table")
    return false
  end

  local ok = true
  for surface, actions in pairs(keymaps) do
    local known = M.defaults.keymaps[surface]
    if known == nil then
      warn(string.format("unknown keymap surface %q (expected diff, files, or thread)", surface))
      ok = false
    elseif type(actions) ~= "table" then
      warn(string.format("keymaps.%s must be a table", surface))
      ok = false
    else
      for action, lhs in pairs(actions) do
        if known[action] == nil then
          warn(string.format("unknown keymap action %q for surface %q", action, surface))
          ok = false
        elseif type(lhs) ~= "string" and lhs ~= false then
          warn(string.format("keymaps.%s.%s must be a string or false", surface, action))
          ok = false
        end
      end
    end
  end
  return ok
end

local function validate_fold(fold)
  if fold == nil then return true end
  if type(fold) ~= "table" then
    warn("fold must be a table or false")
    return false
  end

  local ok = true
  for key, value in pairs(fold) do
    if key == "enabled" then
      if type(value) ~= "boolean" then
        warn("fold.enabled must be a boolean")
        ok = false
      end
    elseif key == "level" then
      if type(value) ~= "number" then
        warn("fold.level must be a number")
        ok = false
      end
    else
      warn(string.format("unknown fold option %q (expected enabled or level)", key))
      ok = false
    end
  end
  return ok
end

-- Accept `fold = false` as shorthand for `fold = { enabled = false }`.
local function normalize(opts)
  opts = vim.deepcopy(opts or {})
  if opts.fold == false then
    opts.fold = { enabled = false }
  end
  return opts
end

-- Merge user options over the defaults. A call containing any invalid key is
-- rejected whole, so a typo fails loudly rather than half-applying.
function M.setup(opts)
  opts = normalize(opts)

  local ok = true
  for key in pairs(opts) do
    if key ~= "fold" and key ~= "keymaps" then
      warn(string.format("unknown option %q (expected fold or keymaps)", key))
      ok = false
    end
  end
  if not validate_fold(opts.fold) then ok = false end
  if not validate_keymaps(opts.keymaps) then ok = false end
  if not ok then return end

  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
end

-- Apply a module's ACTIONS declaration to a buffer using the configured keys.
-- `actions` maps an action name to a list of { mode, handler, desc } triples;
-- one action may own several mappings across modes with distinct handlers.
-- Actions configured as `false` are skipped.
function M.apply_keymaps(bufnr, surface, actions)
  local configured = M.options.keymaps[surface]
  for action, bindings in pairs(actions) do
    local lhs = configured[action]
    if type(lhs) == "string" then
      for _, binding in ipairs(bindings) do
        local mode, handler, desc = binding[1], binding[2], binding[3]
        vim.keymap.set(mode, lhs, handler, { buffer = bufnr, silent = true, desc = desc })
      end
    end
  end
end

-- Remove the mappings apply_keymaps would have set. Walks the same declaration
-- rather than a separate list, so the two cannot drift apart.
function M.clear_keymaps(bufnr, surface, actions)
  local configured = M.options.keymaps[surface]
  for action, bindings in pairs(actions) do
    local lhs = configured[action]
    if type(lhs) == "string" then
      for _, binding in ipairs(bindings) do
        pcall(vim.keymap.del, binding[1], lhs, { buffer = bufnr })
      end
    end
  end
end

-- Window options to apply after :diffthis.
--
-- :diffthis sets foldmethod=diff itself and leaves foldlevel at 0, so turning
-- folding off means actively setting foldenable=false -- not merely declining
-- to set foldmethod, which would have no effect at all.
function M.fold_settings()
  if not M.options.fold.enabled then
    return { foldenable = false }
  end
  return { foldenable = true, foldlevel = M.options.fold.level }
end

return M
