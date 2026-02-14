-- Async wrapper around the `gh` CLI.

local M = {}

-- Run an arbitrary command asynchronously.
-- Callback receives (stdout, stderr, exit_code).
function M.run_cmd_async(cmd, callback)
  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      callback(obj.stdout or "", obj.stderr or "", obj.code)
    end)
  end)
end

-- Run a gh command asynchronously.  Callback receives (stdout, stderr).
function M.run_async(cmd, callback)
  local full = { "gh" }
  for _, v in ipairs(cmd) do
    full[#full + 1] = v
  end
  M.run_cmd_async(full, function(stdout, stderr, _)
    callback(stdout, stderr)
  end)
end

-- Run a GraphQL query/mutation.  Callback receives the parsed table.
function M.graphql(query, variables, callback)
  local cmd = { "api", "graphql" }
  for key, val in pairs(variables) do
    -- -f passes as string, -F passes as JSON (needed for Int, Boolean, etc.)
    local flag = type(val) == "string" and "-f" or "-F"
    cmd[#cmd + 1] = flag
    cmd[#cmd + 1] = key .. "=" .. tostring(val)
  end
  cmd[#cmd + 1] = "-f"
  cmd[#cmd + 1] = "query=" .. query

  M.run_async(cmd, function(stdout, stderr)
    if stderr and stderr ~= "" then
      vim.notify("[gh-review] GraphQL error: " .. stderr, vim.log.levels.ERROR)
      return
    end
    local ok, parsed = pcall(vim.json.decode, stdout)
    if not ok then
      vim.notify("[gh-review] Failed to parse GraphQL response", vim.log.levels.ERROR)
      return
    end
    if parsed.errors and #parsed.errors > 0 then
      vim.notify("[gh-review] GraphQL error: " .. tostring(parsed.errors[1].message), vim.log.levels.ERROR)
      return
    end
    callback(parsed)
  end)
end

return M
