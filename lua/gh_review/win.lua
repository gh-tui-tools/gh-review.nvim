-- Window helpers shared by the files list, diff, and thread buffers.

local M = {}

-- Close the current window, or empty it when it is the last one.
--
-- `:close` raises E444 on the last window. An error there aborts whatever
-- teardown was running: for `M.close()` that means never reaching the buffer
-- wipe or `state.reset()`, leaving the plugin half-open with the files list
-- still on screen. Sitting in a review with the files list as the only window
-- is an ordinary thing to do, so this is reachable in normal use.
--
-- Emptying the window keeps teardown going, and keeps `q` in a review buffer
-- from being a way to quit Neovim. Whichever review buffer the window held is
-- then undisplayed, so the caller can wipe it.
function M.close_current()
  if not pcall(vim.cmd, "close") then
    vim.cmd("enew")
  end
end

return M
