-- Tests for choosing the base remote and finding a repo's remote.

local h = require("test.helpers")
local remotes = require("gh_review.remotes")

local function remote(name, resolved)
  return { name = name, url = "https://github.com/" .. name .. "/repo.git", resolved = resolved or "" }
end

h.run_test("Base remote: the one gh repo set-default marked wins", function()
  local list = { remote("origin"), remote("upstream"), remote("mine", "base") }
  h.assert_equal("mine", remotes.pick_base(list).name)
end)

h.run_test("Base remote: upstream, then github, then origin", function()
  h.assert_equal("upstream", remotes.pick_base({ remote("origin"), remote("github"), remote("upstream") }).name)
  h.assert_equal("github", remotes.pick_base({ remote("origin"), remote("github") }).name)
  h.assert_equal("origin", remotes.pick_base({ remote("fork"), remote("origin") }).name)
end)

h.run_test("Base remote: otherwise the first remote, or nil", function()
  h.assert_equal("fork", remotes.pick_base({ remote("fork"), remote("other") }).name)
  h.assert_equal(nil, remotes.pick_base({}))
end)

h.run_test("Find the remote for a repo by host, owner, and name", function()
  local list = {
    { name = "origin", url = "https://github.com/fork_user/repo.git", resolved = "" },
    { name = "upstream", url = "https://github.com/Upstream_User/Repo", resolved = "" },
    { name = "ghe", url = "https://git.example.com/upstream_user/repo.git", resolved = "" },
  }
  h.assert_equal("upstream", remotes.find(list, "github.com", "upstream_user", "repo"))
  h.assert_equal("origin", remotes.find(list, "github.com", "fork_user", "repo"))
  h.assert_equal("ghe", remotes.find(list, "git.example.com", "upstream_user", "repo"))
  h.assert_equal(nil, remotes.find(list, "github.com", "someone_else", "repo"))
end)

h.run_test("List remotes with their gh-resolved config", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local prev = vim.fn.getcwd()
  vim.fn.chdir(dir)
  vim.system({ "git", "init", "-q" }):wait()
  vim.system({ "git", "remote", "add", "origin", "https://github.com/fork_user/repo.git" }):wait()
  vim.system({ "git", "remote", "add", "my.upstream", "https://github.com/upstream_user/repo.git" }):wait()
  vim.system({ "git", "config", "remote.my.upstream.gh-resolved", "base" }):wait()
  local list = remotes.list()
  vim.fn.chdir(prev)
  vim.fn.delete(dir, "rf")

  h.assert_equal(2, #list)
  local by_name = {}
  for _, r in ipairs(list) do by_name[r.name] = r end
  h.assert_equal("https://github.com/fork_user/repo.git", by_name["origin"].url)
  h.assert_equal("", by_name["origin"].resolved)
  h.assert_equal("base", by_name["my.upstream"].resolved)
  h.assert_equal("my.upstream", remotes.pick_base(list).name)
end)

h.write_results("/tmp/gh_review_test_remotes.txt")
