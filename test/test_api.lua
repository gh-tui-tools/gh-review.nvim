-- Tests for lua/gh_review/api.lua: dropping duplicate writes.

local h = require("test.helpers")
local api = require("gh_review.api")

-- Replace the process runner with one that holds each request until the test
-- calls `finish(i)`. `started[i]` is the i-th command started.
local function with_fake_runner(fn)
  local original, orig_notify = api.run_cmd_async, vim.notify
  local started, pending, notes = {}, {}, {}
  api.run_cmd_async = function(cmd, cb)
    started[#started + 1] = cmd
    pending[#started] = cb
  end
  vim.notify = function(msg) notes[#notes + 1] = msg end
  local function finish(i)
    local cb = pending[i]
    pending[i] = nil
    cb("{}", "", 0)
  end
  local ok, err = pcall(fn, started, finish, notes)
  -- Answer whatever the test left open, so no write stays in flight for the
  -- next test.
  for i in pairs(pending) do pcall(finish, i) end
  api.run_cmd_async, vim.notify = original, orig_notify
  if not ok then error(err, 0) end
end

h.run_test("A write identical to one in flight is dropped", function()
  with_fake_runner(function(started, finish, notes)
    local calls = 0
    local vars = { body = "hi", threadId = "T1" }
    h.assert_true(api.graphql("mutation { add }", vars, function() calls = calls + 1 end))
    h.assert_false(api.graphql("mutation { add }", vars, function() calls = calls + 1 end))
    h.assert_equal(1, #started)
    h.assert_match("already in progress", notes[1])
    finish(1)
    h.assert_equal(1, calls)
  end)
end)

h.run_test("A read between two identical writes does not hide the duplicate", function()
  with_fake_runner(function()
    h.assert_true(api.graphql("mutation { add }", { body = "x" }, function() end))
    h.assert_true(api.graphql("query { threads }", {}, function() end))
    h.assert_false(api.graphql("mutation { add }", { body = "x" }, function() end))
  end)
end)

h.run_test("Identical reads are never dropped", function()
  with_fake_runner(function(started)
    h.assert_true(api.graphql("query { threads }", {}, function() end))
    h.assert_true(api.graphql("query { threads }", {}, function() end))
    h.assert_equal(2, #started)
  end)
end)

h.run_test("A write may repeat once a different write came after it", function()
  with_fake_runner(function()
    h.assert_true(api.graphql("mutation { mark }", { path = "a" }, function() end))
    h.assert_true(api.graphql("mutation { unmark }", { path = "a" }, function() end))
    h.assert_true(api.graphql("mutation { mark }", { path = "a" }, function() end))
  end)
end)

h.run_test("A write may repeat after the first one finished", function()
  with_fake_runner(function(_, finish)
    api.graphql("mutation { add }", { body = "x" }, function() end)
    finish(1)
    h.assert_true(api.graphql("mutation { add }", { body = "x" }, function() end))
  end)
end)

h.run_test("A write may repeat after the first one's callback errored", function()
  with_fake_runner(function(_, finish)
    api.graphql("mutation { add }", { body = "x" }, function() error("boom") end)
    h.assert_false(pcall(finish, 1))
    h.assert_true(api.graphql("mutation { add }", { body = "x" }, function() end))
  end)
end)

h.run_test("Writes with different variables are not duplicates", function()
  with_fake_runner(function()
    h.assert_true(api.graphql("mutation { add }", { body = "x" }, function() end))
    h.assert_true(api.graphql("mutation { add }", { body = "y" }, function() end))
  end)
end)

h.run_test("A REST call with fields is a write; a GET is not", function()
  with_fake_runner(function()
    local post = { "api", "/repos/o/r/pulls/1/comments/2/replies", "-f", "body=x" }
    h.assert_true(api.run_async(post, function() end))
    h.assert_false(api.run_async(post, function() end))
    local get = { "api", "/repos/o/r/compare/a...b" }
    h.assert_true(api.run_async(get, function() end))
    h.assert_true(api.run_async(get, function() end))
    local explicit_get = { "api", "-X", "GET", "/search", "-f", "q=x" }
    h.assert_true(api.run_async(explicit_get, function() end))
    h.assert_true(api.run_async(explicit_get, function() end))
  end)
end)

h.run_test("Variables build the same command whatever the insertion order", function()
  with_fake_runner(function(started)
    local a = {}
    a.x, a.y, a.z = "1", "2", "3"
    local b = {}
    b.z, b.y, b.x = "3", "2", "1"
    api.graphql("query { q }", a, function() end)
    api.graphql("query { q }", b, function() end)
    h.assert_true(vim.deep_equal(started[1], started[2]), vim.inspect(started))
  end)
end)

h.write_results("/tmp/gh_review_test_api.txt")
