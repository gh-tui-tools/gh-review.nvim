-- Parsing for Git remote URLs and PR URLs.

local M = {}

-- Split a Git remote URL into its host, owner, and repo name.  Handles URLs
-- with a scheme (https://host/owner/name.git, ssh://git@host:2222/owner/name)
-- and scp-like ones (git@host:owner/name.git).  Returns nil for anything else,
-- such as a local path.  The ssh field is true unless the remote is HTTP(S):
-- Its host is then an SSH host, which can differ from the web host.
function M.parse_remote(remote)
  local host, path, ssh
  local scheme, authority, rest = remote:match("^([%w+.-]+)://([^/]+)/(.+)$")
  if scheme then
    ssh = not scheme:match("^https?$")
    host = authority:gsub("^.*@", "")
    -- An SSH port says nothing about the web host, so drop it.
    if ssh then host = host:gsub(":%d+$", "") end
    path = rest
  else
    authority, rest = remote:match("^([^:/]+):(.+)$")
    if not authority then return nil end
    ssh = true
    host = authority:gsub("^.*@", "")
    path = rest
  end
  local owner, name = path:match("^([^/]+)/([^/]+)")
  if not owner then return nil end
  name = name:gsub("%.git$", "")
  return { host = host:lower(), owner = owner, name = name, ssh = ssh }
end

-- The web host for a parsed remote.  An SSH host can be an alias from the
-- user's SSH config (git@github-work:owner/name), so ask ssh what it resolves
-- to.  And ssh.github.com is the SSH-over-443 endpoint for github.com.
function M.web_host(info)
  local host = info.host
  if info.ssh and vim.fn.executable("ssh") == 1 then
    local obj = vim.system({ "ssh", "-G", host }, { text = true }):wait()
    local resolved = obj.code == 0 and ("\n" .. (obj.stdout or "")):match("\nhostname (%S+)")
    if resolved then host = resolved:lower() end
  end
  if host == "ssh.github.com" then host = "github.com" end
  return host
end

-- Parse a :GHReview argument: a PR URL from any host, with or without its
-- scheme, or a plain PR number.  Fields not given by the argument are empty
-- strings; number is nil if the argument is neither form.
function M.parse_pr_arg(arg)
  local rest = arg:gsub("^https?://", "")
  local host, owner, name, num = rest:match("^([^/]+)/([^/]+)/([^/]+)/pull/(%d+)")
  if host then
    return { host = host:lower(), owner = owner, name = name, number = tonumber(num) }
  end
  return { host = "", owner = "", name = "", number = tonumber(arg) }
end

-- The URL of a fork of the repo at remote: the same URL with owner/name
-- swapped for fork_owner/fork_name, so the fork remote keeps the user, port,
-- host alias, and protocol of the original.  Returns nil if remote doesn't end
-- with owner/name.
function M.fork_url(remote, owner, name, fork_owner, fork_name)
  local base, suffix = remote:match("^(.-)(%.git/?)$")
  if not base then base, suffix = remote:match("^(.-)(/?)$") end
  local tail = owner .. "/" .. name
  local start = #base - #tail + 1
  local sep = base:sub(start - 1, start - 1)
  if start < 2 or base:sub(start):lower() ~= tail:lower() or (sep ~= "/" and sep ~= ":") then
    return nil
  end
  return base:sub(1, start - 1) .. fork_owner .. "/" .. fork_name .. suffix
end

return M
