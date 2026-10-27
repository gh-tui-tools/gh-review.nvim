-- Tests for Git remote URL parsing and fork URL derivation.

local h = require("test.helpers")
local url = require("gh_review.url")

local function assert_remote(remote, host, owner, name, ssh)
  local info = url.parse_remote(remote)
  h.assert_true(info ~= nil, "should parse " .. remote)
  h.assert_equal(host, info.host, remote)
  h.assert_equal(owner, info.owner, remote)
  h.assert_equal(name, info.name, remote)
  h.assert_equal(ssh, info.ssh, remote)
end

h.run_test("Parse scp-like SSH remotes", function()
  assert_remote("git@github.com:owner/repo.git", "github.com", "owner", "repo", true)
  assert_remote("git@git.example.com:team/project", "git.example.com", "team", "project", true)
  assert_remote("github-work:owner/repo.git", "github-work", "owner", "repo", true)
end)

h.run_test("Parse ssh:// remotes, dropping the port", function()
  assert_remote("ssh://git@github.com/owner/repo.git", "github.com", "owner", "repo", true)
  assert_remote("ssh://git@git.example.com:7999/team/project.git", "git.example.com", "team", "project", true)
end)

h.run_test("Parse HTTPS remotes", function()
  assert_remote("https://github.com/owner/repo.git", "github.com", "owner", "repo", false)
  assert_remote("https://user@GIT.example.com/team/project", "git.example.com", "team", "project", false)
end)

h.run_test("Unparseable remotes return nil", function()
  h.assert_equal(nil, url.parse_remote("/path/to/repo.git"))
  h.assert_equal(nil, url.parse_remote("https://github.com/owner"))
  h.assert_equal(nil, url.parse_remote(""))
end)

h.run_test("Web host maps ssh.github.com to github.com", function()
  h.assert_equal("github.com", url.web_host({ host = "ssh.github.com", ssh = false }))
  h.assert_equal("git.example.com", url.web_host({ host = "git.example.com", ssh = false }))
end)

h.run_test("Fork URL keeps everything but owner and name", function()
  h.assert_equal("git@github.com:fork/repo.git",
    url.fork_url("git@github.com:owner/repo.git", "owner", "repo", "fork", "repo"))
  h.assert_equal("ssh://git@git.example.com:7999/fork/renamed.git",
    url.fork_url("ssh://git@git.example.com:7999/team/project.git", "team", "project", "fork", "renamed"))
  h.assert_equal("https://github.com/fork/repo",
    url.fork_url("https://github.com/owner/repo", "owner", "repo", "fork", "repo"))
  h.assert_equal("https://github.com/fork/repo.git/",
    url.fork_url("https://github.com/Owner/Repo.git/", "owner", "repo", "fork", "repo"))
end)

h.run_test("Fork URL is nil when origin is a different repo", function()
  h.assert_equal(nil, url.fork_url("git@github.com:owner/other.git", "owner", "repo", "fork", "repo"))
  h.assert_equal(nil, url.fork_url("git@github.com:xowner/repo.git", "owner", "repo", "fork", "repo"))
end)

h.write_results("/tmp/gh_review_test_url.txt")
