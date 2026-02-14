-- Shared test helpers for gh-review.nvim test suite.
-- Require this at the top of every test file.

local M = {}

-- Source the plugin file so signs/highlights/commands are defined
vim.cmd("source " .. vim.fn.getcwd() .. "/plugin/gh_review.lua")

-- Allow hidden buffers so tests can switch away from modified buffers
vim.o.hidden = true

-- Test infrastructure
M.test_results = {}

function M.run_test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.test_results[#M.test_results + 1] = "PASS: " .. name
  else
    M.test_results[#M.test_results + 1] = "FAIL: " .. name .. " - " .. tostring(err)
  end
end

function M.assert_equal(expected, actual, msg)
  if expected ~= actual then
    msg = msg or ""
    error(string.format("Expected %s but got %s. %s",
      vim.inspect(expected), vim.inspect(actual), msg), 2)
  end
end

function M.assert_true(val, msg)
  if not val then
    error("Expected truthy but got " .. vim.inspect(val) .. ". " .. (msg or ""), 2)
  end
end

function M.assert_false(val, msg)
  if val then
    error("Expected falsy but got " .. vim.inspect(val) .. ". " .. (msg or ""), 2)
  end
end

function M.assert_match(pattern, str, msg)
  if not str:find(pattern) then
    error(string.format("Pattern '%s' not found in '%s'. %s",
      pattern, str, msg or ""), 2)
  end
end

function M.write_results(filename)
  vim.fn.writefile(M.test_results, filename)
  vim.cmd("qall!")
end

return M
