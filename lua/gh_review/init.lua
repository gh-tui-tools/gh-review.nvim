-- Top-level orchestration for gh-review.nvim.

local api_mod = require("gh_review.api")
local graphql = require("gh_review.graphql")
local state = require("gh_review.state")
local files = require("gh_review.files")
local diff = require("gh_review.diff")
local thread = require("gh_review.thread")

local M = {}

local function is_local_repo(owner, name)
  local obj = vim.system({ "git", "remote", "get-url", "origin" }, { text = true }):wait()
  if obj.code ~= 0 then return false end
  local remote = vim.trim(obj.stdout or "")
  return remote:find(owner .. "/" .. name, 1, true) ~= nil
end

local function setup_push_tracking(local_branch)
  local head_owner = state.get_head_repo_owner()
  local head_name = state.get_head_repo_name()
  local head_branch = state.get_head_ref()
  local repo_owner = state.get_owner()

  local remote
  if head_owner == repo_owner then
    remote = "origin"
  else
    -- Fork PR -- ensure a remote exists for the fork.
    remote = head_owner
    local obj = vim.system({ "git", "remote", "get-url", remote }, { text = true }):wait()
    if obj.code ~= 0 then
      -- Add remote, matching origin's protocol (SSH vs HTTPS).
      local origin_obj = vim.system({ "git", "remote", "get-url", "origin" }, { text = true }):wait()
      local origin_url = vim.trim(origin_obj.stdout or "")
      local fork_url
      if origin_url:match("^git@") then
        fork_url = string.format("git@github.com:%s/%s.git", head_owner, head_name)
      else
        fork_url = string.format("https://github.com/%s/%s.git", head_owner, head_name)
      end
      local add_obj = vim.system({ "git", "remote", "add", remote, fork_url }, { text = true }):wait()
      if add_obj.code ~= 0 then
        vim.notify(string.format("[gh-review] Could not add remote for fork %s", remote), vim.log.levels.WARN)
        return
      end
    end
  end

  local cfg1 = vim.system({ "git", "config",
    "branch." .. local_branch .. ".remote", remote }, { text = true }):wait()
  if cfg1.code ~= 0 then
    vim.notify("[gh-review] Could not configure push tracking", vim.log.levels.WARN)
    return
  end
  local cfg2 = vim.system({ "git", "config",
    "branch." .. local_branch .. ".merge", "refs/heads/" .. head_branch }, { text = true }):wait()
  if cfg2.code ~= 0 then
    vim.notify("[gh-review] Could not configure push tracking", vim.log.levels.WARN)
  end
end

local function fetch_merge_base(callback)
  local owner = state.get_owner()
  local name = state.get_name()
  local base = state.get_base_ref()
  local head = state.get_head_ref()

  -- Try local git merge-base first
  local obj = vim.system({ "git", "merge-base",
    "origin/" .. base, "origin/" .. head }, { text = true }):wait()

  if obj.code == 0 and vim.trim(obj.stdout or "") ~= "" then
    state.set_merge_base_oid(vim.trim(obj.stdout))
    callback()
    return
  end

  -- Fall back to REST compare endpoint
  local endpoint = string.format("/repos/%s/%s/compare/%s...%s", owner, name, base, head)
  api_mod.run_async({ "api", endpoint }, function(stdout, stderr)
    if stderr == "" or stderr == nil then
      local ok, parsed = pcall(vim.json.decode, stdout)
      if ok then
        local commit = (parsed or {}).merge_base_commit or {}
        if commit.sha then
          state.set_merge_base_oid(commit.sha)
        end
      end
    end
    -- Use base OID as fallback if merge base is still empty
    if state.get_merge_base_oid() == "" then
      vim.notify("[gh-review] Could not determine merge base; diff may be inaccurate", vim.log.levels.WARN)
      state.set_merge_base_oid(state.get_base_oid())
    end
    callback()
  end)
end

-- Open a PR for review.
function M.open(pr_number_str)
  pr_number_str = pr_number_str or ""

  if vim.fn.executable("gh") ~= 1 then
    vim.notify("[gh-review] `gh` CLI not found. Install it from https://cli.github.com", vim.log.levels.ERROR)
    return
  end

  local pr_number
  local url_owner = ""
  local url_name = ""

  if pr_number_str == "" then
    print("Detecting PR for current branch...")
    local obj = vim.system(
      { "gh", "pr", "view", "--json", "number", "-q", ".number" },
      { text = true }):wait()
    if obj.code ~= 0 or vim.trim(obj.stdout or "") == "" then
      vim.notify("[gh-review] No PR found for the current branch", vim.log.levels.ERROR)
      return
    end
    pr_number = tonumber(vim.trim(obj.stdout))
  else
    -- Accept a full GitHub PR URL or a plain number
    local o, n, num = pr_number_str:match("github%.com/([^/]+)/([^/]+)/pull/(%d+)")
    if o then
      url_owner = o
      url_name = n
      pr_number = tonumber(num)
    else
      pr_number = tonumber(pr_number_str)
    end
  end

  if not pr_number or pr_number <= 0 then
    vim.notify("[gh-review] Invalid PR number or URL: " .. pr_number_str, vim.log.levels.ERROR)
    return
  end

  -- Determine repo and whether checkout is possible.
  local should_checkout = false
  if url_owner ~= "" then
    state.set_repo_info(url_owner, url_name)
    should_checkout = is_local_repo(url_owner, url_name)
  else
    if not state.get_repo_info() then return end
    should_checkout = true
  end

  state.set_local_checkout(should_checkout)

  print(string.format("Loading PR #%d...", pr_number))

  local owner = state.get_owner()
  local name = state.get_name()

  local vars = {
    owner = owner,
    name = name,
    number = pr_number,
  }
  api_mod.graphql(graphql.QUERY_PR_DETAILS, vars, function(result)
    local pr = (((result or {}).data or {}).repository or {}).pullRequest
    if not pr then
      vim.notify("[gh-review] Failed to load PR details", vim.log.levels.ERROR)
      return
    end

    state.set_pr(result)

    local thread_nodes = ((pr.reviewThreads or {}).nodes or {})
    state.set_threads(thread_nodes)

    local function load_ui()
      fetch_merge_base(function()
        files.open()
        print(string.format("PR #%d loaded: %s", state.get_pr_number(), state.get_pr_title()))
      end)
    end

    if should_checkout then
      local local_branch = state.get_head_ref()
      local obj = vim.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }):wait()
      local current_branch = vim.trim(obj.stdout or "")
      if current_branch == local_branch then
        load_ui()
        return
      end

      vim.ui.select({ "Yes", "No" }, {
        prompt = string.format("Check out branch %s?", local_branch),
      }, function(choice)
        if choice ~= "Yes" then
          should_checkout = false
          state.set_local_checkout(false)
          load_ui()
          return
        end

        local fetch_ref = string.format("pull/%d/head", pr_number)
        api_mod.run_cmd_async({ "git", "fetch", "origin", fetch_ref }, function(_, fe, fetch_exit)
          if fetch_exit ~= 0 then
            vim.notify("[gh-review] Could not fetch PR branch: " .. vim.trim(fe), vim.log.levels.WARN)
            state.set_local_checkout(false)
            load_ui()
          else
            api_mod.run_cmd_async({ "git", "checkout", "-B", local_branch, "FETCH_HEAD" }, function(_, ce, co_exit)
              if co_exit == 0 then
                setup_push_tracking(local_branch)
                vim.notify(string.format("[gh-review] Checked out branch %s", local_branch))
              else
                vim.notify("[gh-review] Could not check out PR branch: " .. vim.trim(ce), vim.log.levels.WARN)
                state.set_local_checkout(false)
              end
              load_ui()
            end)
          end
        end)
      end)
    else
      load_ui()
    end
  end)
end

-- Toggle the files list.
function M.toggle_files()
  files.toggle()
end

-- Start a pending review.
function M.start_review()
  if state.is_review_active() then
    print("A pending review is already active")
    return
  end

  if state.get_pr_id() == "" then
    vim.notify("[gh-review] No PR loaded. Use :GHReview {number|url} first.", vim.log.levels.ERROR)
    return
  end

  print("Starting review...")
  local start_vars = { pullRequestId = state.get_pr_id() }
  api_mod.graphql(graphql.MUTATION_START_REVIEW, start_vars, function(result)
    local review = ((((result or {}).data or {}).addPullRequestReview or {}).pullRequestReview or {})
    if review and review.id then
      state.set_pending_review_id(review.id)
      print("Review started. Comments will be held as pending until you submit.")
    else
      vim.notify("[gh-review] Failed to start review", vim.log.levels.ERROR)
    end
  end)
end

-- Submit a review.
function M.submit_review()
  if state.get_pr_id() == "" then
    vim.notify("[gh-review] No PR loaded. Use :GHReview {number|url} first.", vim.log.levels.ERROR)
    return
  end

  local event_map = { Comment = "COMMENT", Approve = "APPROVE", ["Request changes"] = "REQUEST_CHANGES" }
  vim.ui.select({ "Comment", "Approve", "Request changes" }, {
    prompt = "Submit review as:",
  }, function(choice)
    if not choice then return end
    local event = event_map[choice]

    local function do_submit(body)
      body = body or ""
      print("Submitting review...")

      if state.is_review_active() then
        local vars = {
          reviewId = state.get_pending_review_id(),
          event = event,
        }
        if body ~= "" then vars.body = body end

        api_mod.graphql(graphql.MUTATION_SUBMIT_REVIEW, vars, function(result)
          local review = ((((result or {}).data or {}).submitPullRequestReview or {}).pullRequestReview or {})
          if review and review.id then
            state.set_pending_review_id("")
            print("Review submitted as " .. event)
            M.refresh_threads()
          else
            vim.notify("[gh-review] Failed to submit review", vim.log.levels.ERROR)
          end
        end)
      else
        local vars = {
          pullRequestId = state.get_pr_id(),
          event = event,
        }
        if body ~= "" then vars.body = body end

        api_mod.graphql(graphql.MUTATION_CREATE_AND_SUBMIT_REVIEW, vars, function(result)
          local review = ((((result or {}).data or {}).addPullRequestReview or {}).pullRequestReview or {})
          if review and review.id then
            print("Review submitted as " .. event)
            M.refresh_threads()
          else
            vim.notify("[gh-review] Failed to submit review", vim.log.levels.ERROR)
          end
        end)
      end
    end

    if event == "COMMENT" or event == "REQUEST_CHANGES" then
      vim.ui.input({ prompt = "Review body (optional): " }, function(body)
        do_submit(body or "")
      end)
    else
      do_submit("")
    end
  end)
end

-- Discard the pending review.
function M.discard_review()
  if not state.is_review_active() then
    vim.notify("[gh-review] No pending review to discard.", vim.log.levels.ERROR)
    return
  end

  vim.ui.select({ "Yes", "No" }, {
    prompt = "Discard pending review and all its comments?",
  }, function(choice)
    if choice ~= "Yes" then return end

    print("Discarding review...")
    local vars = { pullRequestReviewId = state.get_pending_review_id() }
    api_mod.graphql(graphql.MUTATION_DELETE_REVIEW, vars, function(result)
      local review = ((((result or {}).data or {}).deletePullRequestReview or {}).pullRequestReview or {})
      if review and review.id then
        state.set_pending_review_id("")
        M.refresh_threads()
        print("Pending review discarded")
      else
        vim.notify("[gh-review] Failed to discard review", vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Refresh threads from GitHub and update signs/files list.
function M.refresh_threads()
  if state.get_pr_id() == "" then return end

  local refresh_vars = {
    owner = state.get_owner(),
    name = state.get_name(),
    number = state.get_pr_number(),
  }
  api_mod.graphql(graphql.QUERY_REVIEW_THREADS, refresh_vars, function(result)
    local pr = (((result or {}).data or {}).repository or {}).pullRequest
    local thread_nodes = ((pr or {}).reviewThreads or {}).nodes or {}
    state.set_threads(thread_nodes)
    diff.refresh_signs()
    files.rerender()
    print("Threads refreshed")
  end)
end

-- Statusline component for integration with statusline plugins.
function M.statusline()
  if state.get_pr_id() == "" then
    return ""
  end
  local parts = { string.format("PR #%d", state.get_pr_number()) }
  if state.is_review_active() then
    parts[#parts + 1] = "reviewing"
  end
  local thread_count = 0
  for _ in pairs(state.get_threads()) do
    thread_count = thread_count + 1
  end
  if thread_count > 0 then
    parts[#parts + 1] = string.format("%d thread%s", thread_count, thread_count > 1 and "s" or "")
  end
  return table.concat(parts, " · ")
end

-- Close all review buffers and reset state.
function M.close()
  thread.close_thread_buffer()
  diff.close_diff()
  files.close()

  -- Wipe any remaining gh-review buffers
  for _, bufinfo in ipairs(vim.fn.getbufinfo()) do
    if bufinfo.name:match("^gh%-review://") then
      vim.cmd("silent! bwipeout! " .. bufinfo.bufnr)
    end
  end

  state.reset()
  print("Review closed")
end

return M
