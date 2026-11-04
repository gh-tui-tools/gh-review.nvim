-- The clone's Git remotes, and which of them holds the PRs.

local url = require("gh_review.url")

local M = {}

-- Remote names gh prefers for the base repo, most preferred first.
local PREFERRED = { "upstream", "github", "origin" }

-- The clone's remotes, in the order Git lists them: a list of tables with the
-- remote's name, its fetch URL, and its gh-resolved config value ("" if unset).
function M.list()
  local result = {}
  local obj = vim.system({ "git", "remote", "-v" }, { text = true }):wait()
  if obj.code ~= 0 then return result end
  for line in (obj.stdout or ""):gmatch("[^\n]+") do
    local name, remote_url = line:match("^(%S+)%s+(%S+)%s+%(fetch%)$")
    if name then
      result[#result + 1] = { name = name, url = remote_url, resolved = "" }
    end
  end

  local cfg = vim.system({ "git", "config", "--get-regexp", "^remote\\..*\\.gh-resolved$" }, { text = true }):wait()
  for line in (cfg.stdout or ""):gmatch("[^\n]+") do
    local name, value = line:match("^remote%.(.+)%.gh%-resolved%s+(.*)$")
    for _, r in ipairs(result) do
      if r.name == name then r.resolved = value end
    end
  end
  return result
end

-- The remote for the base repo -- the one gh's own commands use, so a PR number
-- means the same PR here as in "gh pr view".  That's the remote "gh repo
-- set-default" marked; otherwise the first of upstream, github, and origin; and
-- otherwise the first remote.  So in a clone of a fork, it's the fork's parent.
-- Returns nil if there are no remotes.
function M.pick_base(remotes)
  for _, r in ipairs(remotes) do
    if r.resolved == "base" then return r end
  end
  for _, name in ipairs(PREFERRED) do
    for _, r in ipairs(remotes) do
      if r.name == name then return r end
    end
  end
  return remotes[1]
end

-- The name of the remote for the repo host/owner/name, or nil if no remote
-- points at it.
function M.find(remotes, host, owner, name)
  for _, r in ipairs(remotes) do
    local info = url.parse_remote(r.url)
    if info
      and info.owner:lower() == owner:lower()
      and info.name:lower() == name:lower()
      and url.web_host(info) == host:lower() then
      return r.name
    end
  end
  return nil
end

return M
