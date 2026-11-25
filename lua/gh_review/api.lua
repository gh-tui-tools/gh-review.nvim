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

-- Writes sent and not yet answered, oldest first.
local in_flight = {}

-- Writes change GitHub state. A read never is.
local function is_write(cmd)
  if cmd[2] == "graphql" then
    for _, v in ipairs(cmd) do
      local q = v:match("^query=(.*)")
      if q then return q:match("^%s*mutation") ~= nil end
    end
    return false
  end
  local has_fields = false
  for i, v in ipairs(cmd) do
    if v == "-X" or v == "--method" then
      return (cmd[i + 1] or ""):upper() ~= "GET"
    end
    if v == "-f" or v == "-F" or v == "--field" or v == "--raw-field" then
      has_fields = true
    end
  end
  -- `gh api` switches to POST when fields are given without a method.
  return has_fields
end

-- GitHub documents no idempotency key for its REST or GraphQL API, and
-- GraphQL's `clientMutationId` is only echoed back. So pressing
-- submit twice while the first request is in flight would post the comment
-- twice. Drop a write that is identical to the last write still in flight.
-- Only the last one counts: mark, unmark, mark is three real changes.
local function last_write_key()
  return (in_flight[#in_flight] or {}).key
end

-- Run a gh command asynchronously.  Callback receives (stdout, stderr).
-- Returns false, and never calls `callback`, when the request is dropped as a
-- duplicate of a write already in progress.
function M.run_async(cmd, callback)
  local full = { "gh" }
  local host = require("gh_review.state").get_host()
  for i, v in ipairs(cmd) do
    full[#full + 1] = v
    if i == 1 and v == "api" and host ~= "" then
      full[#full + 1] = "--hostname"
      full[#full + 1] = host
    end
  end

  local write
  if is_write(cmd) then
    write = { key = table.concat(full, "\0") }
    if last_write_key() == write.key then
      vim.notify("[gh-review] The same change is already in progress", vim.log.levels.WARN)
      return false
    end
    in_flight[#in_flight + 1] = write
  end
  M.run_cmd_async(full, function(stdout, stderr, _)
    if write then
      for i, w in ipairs(in_flight) do
        if w == write then table.remove(in_flight, i) break end
      end
    end
    callback(stdout, stderr)
  end)
  return true
end

-- Run a GraphQL query/mutation.
-- Callback receives (parsed, err): on success parsed is the decoded table and
-- err is nil; on failure parsed is nil and err is a human-readable message.
-- Returns false when the request is dropped as a duplicate (see run_async).
function M.graphql(query, variables, callback)
  local cmd = { "api", "graphql" }
  -- Sorted so the same variables always build the same command, which the
  -- duplicate check compares.
  local keys = vim.tbl_keys(variables)
  table.sort(keys)
  for _, key in ipairs(keys) do
    local val = variables[key]
    -- -f passes as string, -F passes as JSON (needed for Int, Boolean, etc.)
    local flag = type(val) == "string" and "-f" or "-F"
    cmd[#cmd + 1] = flag
    cmd[#cmd + 1] = key .. "=" .. tostring(val)
  end
  cmd[#cmd + 1] = "-f"
  cmd[#cmd + 1] = "query=" .. query

  return M.run_async(cmd, function(stdout, stderr)
    if stderr and stderr ~= "" then
      local err = "GraphQL error: " .. stderr
      vim.notify("[gh-review] " .. err, vim.log.levels.ERROR)
      callback(nil, err)
      return
    end
    local ok, parsed = pcall(vim.json.decode, stdout)
    if not ok then
      local err = "Failed to parse GraphQL response"
      vim.notify("[gh-review] " .. err, vim.log.levels.ERROR)
      callback(nil, err)
      return
    end
    if parsed.errors and #parsed.errors > 0 then
      local err = "GraphQL error: " .. tostring(parsed.errors[1].message)
      vim.notify("[gh-review] " .. err, vim.log.levels.ERROR)
      callback(nil, err)
      return
    end
    callback(parsed)
  end)
end

return M
