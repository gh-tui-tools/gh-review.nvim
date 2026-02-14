-- PR state management.  Holds all data for the currently active review.

local M = {}

-- Namespace for extmarks (signs, virtual text)
M.ns = vim.api.nvim_create_namespace("gh_review")

-- Helper: get a value from a table, treating vim.NIL as nil.
local function get(t, key, default)
  if t == nil or t == vim.NIL then
    return default
  end
  local val = t[key]
  if val == nil or val == vim.NIL then
    return default
  end
  return val
end

M.get = get

-- PR metadata
local pr_id = ""
local pr_number = 0
local pr_title = ""
local pr_state = ""
local base_ref = ""
local base_oid = ""
local head_ref = ""
local head_oid = ""
local head_repo_owner = ""
local head_repo_name = ""
local merge_base_oid = ""

-- Repo info
local repo_owner = ""
local repo_name = ""

-- Changed files: list of tables with path, additions, deletions, changeType
local changed_files = {}

-- Review threads indexed by id
local threads = {}

-- Pending review id (empty string if no active pending review)
local pending_review_id = ""

-- Buffer and window IDs
local files_bufnr = -1
local left_bufnr = -1
local right_bufnr = -1
local thread_bufnr = -1
local thread_winid = -1

-- Current diff file path
local diff_path = ""
local is_local_checkout = false

-- ------- Getters / Setters -------

function M.get_pr_id() return pr_id end
function M.get_pr_number() return pr_number end
function M.get_pr_title() return pr_title end
function M.get_pr_state() return pr_state end
function M.get_base_ref() return base_ref end
function M.get_base_oid() return base_oid end
function M.get_head_ref() return head_ref end
function M.get_head_oid() return head_oid end
function M.get_head_repo_owner() return head_repo_owner end
function M.get_head_repo_name() return head_repo_name end

function M.get_merge_base_oid() return merge_base_oid end
function M.set_merge_base_oid(oid) merge_base_oid = oid end

function M.get_owner() return repo_owner end
function M.get_name() return repo_name end

function M.get_changed_files() return changed_files end

function M.get_pending_review_id() return pending_review_id end
function M.set_pending_review_id(id) pending_review_id = id end
function M.is_review_active() return pending_review_id ~= "" end

-- Buffer/window accessors

function M.get_files_bufnr() return files_bufnr end
function M.set_files_bufnr(nr) files_bufnr = nr end

function M.get_left_bufnr() return left_bufnr end
function M.set_left_bufnr(nr) left_bufnr = nr end

function M.get_right_bufnr() return right_bufnr end
function M.set_right_bufnr(nr) right_bufnr = nr end

function M.get_thread_bufnr() return thread_bufnr end
function M.set_thread_bufnr(nr) thread_bufnr = nr end

function M.get_thread_winid() return thread_winid end
function M.set_thread_winid(id) thread_winid = id end

function M.get_diff_path() return diff_path end
function M.set_diff_path(path) diff_path = path end

function M.is_local_checkout() return is_local_checkout end
function M.set_local_checkout(val) is_local_checkout = val end

-- ------- PR data loading -------

function M.set_pr(data)
  local pr = data.data.repository.pullRequest
  pr_id = pr.id
  pr_number = pr.number
  pr_title = pr.title
  pr_state = pr.state
  base_ref = pr.baseRefName
  base_oid = pr.baseRefOid
  head_ref = pr.headRefName
  head_oid = pr.headRefOid
  local head_repo = get(pr, "headRepository", nil)
  if head_repo then
    head_repo_owner = head_repo.owner.login
    head_repo_name = head_repo.name
  end

  changed_files = pr.files.nodes

  -- Pick up an existing pending review if one exists
  local reviews = get(pr, "reviews", nil)
  if reviews then
    local nodes = get(reviews, "nodes", {})
    for _, review in ipairs(nodes) do
      if review.state == "PENDING" then
        pending_review_id = review.id
        break
      end
    end
  end
end

function M.set_threads(thread_nodes)
  threads = {}
  for _, t in ipairs(thread_nodes) do
    threads[t.id] = t
  end
end

function M.get_threads() return threads end

function M.get_thread(id)
  return threads[id] or {}
end

function M.set_thread(id, data)
  threads[id] = data
end

function M.get_threads_for_file(path)
  local result = {}
  for _, t in pairs(threads) do
    if get(t, "path", "") == path then
      result[#result + 1] = t
    end
  end
  return result
end

-- ------- Repo detection -------

function M.get_repo_info()
  local obj = vim.system({ "git", "remote", "get-url", "origin" }, { text = true }):wait()
  if obj.code ~= 0 then
    vim.notify("[gh-review] Not in a git repository or no origin remote", vim.log.levels.ERROR)
    return false
  end
  local remote = vim.trim(obj.stdout or "")

  -- Parse SSH format: git@github.com:owner/name.git
  local ssh_owner, ssh_name = remote:match("git@github%.com:([^/]+)/([^/]+)")
  if ssh_owner then
    repo_owner = ssh_owner
    repo_name = ssh_name:gsub("%.git$", "")
    return true
  end

  -- Parse HTTPS format: https://github.com/owner/name.git
  local https_owner, https_name = remote:match("github%.com/([^/]+)/([^/]+)")
  if https_owner then
    repo_owner = https_owner
    repo_name = https_name:gsub("%.git$", "")
    return true
  end

  vim.notify("[gh-review] Could not parse GitHub remote URL: " .. remote, vim.log.levels.ERROR)
  return false
end

function M.set_repo_info(owner, name)
  repo_owner = owner
  repo_name = name
end

-- ------- Participants -------

function M.get_participants()
  local seen = {}
  local result = {}
  for _, t in pairs(threads) do
    local comments_obj = get(t, "comments", {})
    local comments = get(comments_obj, "nodes", {})
    for _, c in ipairs(comments) do
      local author_obj = get(c, "author", {})
      local login = get(author_obj, "login", "")
      if login ~= "" and not seen[login] then
        seen[login] = true
        result[#result + 1] = login
      end
    end
  end
  table.sort(result)
  return result
end

-- ------- Reset -------

function M.reset()
  pr_id = ""
  pr_number = 0
  pr_title = ""
  pr_state = ""
  base_ref = ""
  base_oid = ""
  head_ref = ""
  head_oid = ""
  head_repo_owner = ""
  head_repo_name = ""
  merge_base_oid = ""
  repo_owner = ""
  repo_name = ""
  changed_files = {}
  threads = {}
  pending_review_id = ""
  files_bufnr = -1
  left_bufnr = -1
  right_bufnr = -1
  thread_bufnr = -1
  thread_winid = -1
  diff_path = ""
  is_local_checkout = false
end

return M
